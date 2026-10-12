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
  decodeReconnectPayload,
  decodeTreeSubmissions,
  nativeAdapter,
  publishUpstreamSummary,
  serverHistory,
  success,
  until,
  upstreamAdapter,
} from "./interop-scenarios.mjs";
import {
  handleStoredSchema,
  handleTreeConfig,
  initialHandleRoot,
} from "./schema.mjs";
import {
  reference as sourceReference,
  validateCapture,
  verifyCheckout,
  verifyPackages,
} from "./source.mjs";
import { lifecycleDecodeFieldBatch } from "./generate.mjs";
import { DeliveryGate, storageResponseIdentity } from "./delivery-gate.mjs";

const sections = [
  "handleValues",
  "channelAttachment",
  "datastoreAttachment",
  "handleTransactionBranch",
  "handleRetention",
  "handleReconnect",
  "handleReloadMatrix",
];
const liveSections = sections.slice(0, 6);
const writers = ["upstream", "javascript", "erlang"];
const matrixCheckpoints = [
  "same-datastore",
  "cross-datastore",
  "handle-undo-redo",
];
const matrixCellIds = writers.flatMap((writer) =>
  matrixCheckpoints.flatMap((checkpoint) =>
    writers.map((reader) => `${writer}:${checkpoint}:${reader}`)));
const lifecycleScheduleSeed = 42;
const lifecycleScheduleCount = 300;
const lifecycleScheduleBatchSize = 25;
const sourceCapturePath = join(
  import.meta.dirname,
  ".output/source/source-smoke.json",
);
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

export async function verifyLifecyclePrerequisites({
  capturePath = sourceCapturePath,
  checkoutRoot,
  packagesRoot,
} = {}) {
  const packages = await (packagesRoot === undefined
    ? verifyPackages()
    : verifyPackages(packagesRoot));
  const source = await (checkoutRoot === undefined
    ? verifyCheckout()
    : verifyCheckout(checkoutRoot));
  const bytes = await readFile(capturePath);
  const capture = JSON.parse(bytes);
  validateCapture(capture);
  assert.equal(capture.minVersionForCollab, oldestSupportedClient,
    "Source capture minimum collaboration version changed");
  return {
    packages,
    source,
    capture: {
      reference: capture.reference,
      minVersionForCollab: capture.minVersionForCollab,
      sha256: hash(bytes),
    },
  };
}

function lifecycleSchedulePlans() {
  let state = lifecycleScheduleSeed;
  const random = () => {
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    return state >>> 0;
  };
  return Array.from({ length: lifecycleScheduleCount }, (_, index) => {
    const reconnect = index % 50;
    const mode = reconnect === 0
      ? "disconnect-before-acceptance"
      : reconnect === 25
        ? "disconnect-after-acceptance"
        : ["outbound-held", "inbound-held", "unheld"][random() % 3];
    return {
      id: `lifecycle-${index.toString().padStart(3, "0")}-${random().toString(16).padStart(8, "0")}`,
      index,
      writer: writers[index % writers.length],
      mode,
      releaseOrder: random() % 2 === 0 ? "fifo" : "reverse",
      operationOrder: random() % 2 === 0 ? "target-first" : "parent-first",
    };
  });
}

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

function scheduleHandleReferences(messages) {
  const references = [];
  for (const submission of decodeTreeSubmissions(messages)) {
    const message = messages.find(({ sequenceNumber, clientSequenceNumber, clientId }) =>
      sequenceNumber === submission.outerSequenceNumber
        && clientSequenceNumber === submission.clientSequenceNumber
        && clientId === submission.clientId);
    assert(message, "Schedule decoded submission lacks its sequenced operation");
    for (const commit of submission.commits) {
      for (const change of commit.changeset) {
        const data = change?.data;
        if (!Array.isArray(data?.builds?.builds)
          || !Array.isArray(data.builds?.trees?.data)) continue;
        const fields = lifecycleDecodeFieldBatch(
          data.builds.trees,
          data.builds.trees.data.map((_, index) => String(index)),
          `schedule sequence ${message.sequenceNumber}`,
        );
        const replacements = matchingObjects(
          data.changes,
          (value) => typeof value.fieldKey === "string"
            && Number.isSafeInteger(value.change?.r?.s),
        );
        for (const replacement of replacements) {
          const source = replacement.change.r.s;
          const built = data.builds.builds.flatMap(([mapping]) => mapping)
            .find(([id]) => id === source);
          if (!built) continue;
          const nodes = fields.get(String(built[1]));
          if (nodes?.length !== 1
            || nodes[0].type !== "com.fluidframework.leaf.handle"
            || nodes[0].value?.type !== "__fluid_handle__"
            || typeof nodes[0].value.url !== "string") continue;
          references.push({
            key: replacement.fieldKey,
            path: nodes[0].value.url,
            sequenceNumber: message.sequenceNumber,
            clientSequenceNumber: message.clientSequenceNumber,
            innerIndex: commit.innerIndex,
            revision: commit.revision,
            originatorId: commit.originatorId,
            allocations: jsonClone(submission.allocations),
            message: jsonClone(message),
          });
        }
      }
    }
  }
  return references;
}

function scheduleMapSets(messages, targetPath) {
  const effects = [];
  for (const message of messages) {
    for (const { contents } of operationItems(message)) {
      if (contents?.type !== "component") continue;
      const datastore = contents.contents;
      const channel = datastore?.contents;
      if (channel?.type !== "op") continue;
      const addressed = channel.content;
      if (`/${datastore.address}/${addressed?.address}` !== targetPath) continue;
      const edit = addressed.contents;
      if (edit?.type === "set" && edit.value?.type === "Plain") {
        effects.push({
          target: targetPath,
          key: edit.key,
          value: jsonClone(edit.value.value),
          sequenceNumber: message.sequenceNumber,
          clientSequenceNumber: message.clientSequenceNumber,
          message: jsonClone(message),
        });
      }
    }
  }
  return effects;
}

function scheduleOperationEvidence(messages, plan, target, value) {
  const stageKey = `${plan.id}:stage`;
  const references = scheduleHandleReferences(messages)
    .filter((reference) => reference.path === target.path);
  const attachment = references.filter(({ key }) => key === stageKey);
  const parentReference = references.filter(({ key }) => key === plan.id);
  const targetState = scheduleMapSets(messages, target.path)
    .filter((effect) => effect.key === "value" && effect.value === value);
  assert.equal(attachment.length, 1,
    `${plan.id} lacks one decoded typed-handle channel attachment`);
  assert.equal(parentReference.length, 1,
    `${plan.id} lacks one decoded typed-handle parent reference`);
  assert.equal(targetState.length, 1,
    `${plan.id} lacks one decoded SharedMap state operation`);
  const routes = operationItems(attachment[0].message)
    .flatMap(({ contents }) => attachmentRoutes(contents))
    .filter(({ path }) => path === target.path);
  assert.equal(routes.length, 1,
    `${plan.id} attachment operation lacks the exact channel route`);
  assert(attachment[0].allocations.length > 0,
    `${plan.id} attachment operation lacks decoded allocation evidence`);
  const positions = {
    attachment: position(attachment[0].sequenceNumber, attachment[0].innerIndex),
    "parent-reference": position(
      parentReference[0].sequenceNumber,
      parentReference[0].innerIndex,
    ),
    "target-state": position(targetState[0].sequenceNumber, 0),
  };
  const order = Object.keys(positions).sort((left, right) =>
    comparePosition(positions[left], positions[right]));
  const planned = plan.operationOrder === "target-first"
    ? ["target-state", "parent-reference"]
    : ["parent-reference", "target-state"];
  const reverseAcceptance = plan.mode === "outbound-held"
    && plan.releaseOrder === "reverse";
  const expectedOrder = [
    "attachment",
    ...(reverseAcceptance ? [...planned].reverse() : planned),
  ];
  assert.equal(order[0], "attachment",
    `${plan.id} target operations preceded channel attachment`);
  assert.deepEqual([...order.slice(1)].sort(), [...planned].sort(),
    `${plan.id} executed lifecycle operation set changed`);
  if (plan.mode === "outbound-held") {
    assert.deepEqual(order, expectedOrder,
      `${plan.id} outbound release order differs from its schedule`);
  }
  assert.equal(new Set([
    attachment[0].sequenceNumber,
    parentReference[0].sequenceNumber,
    targetState[0].sequenceNumber,
  ]).size, 3, `${plan.id} lifecycle schedule lacks three accepted operations`);
  return {
    sequenced: jsonClone(messages),
    attachment: attachment[0],
    parentReference: parentReference[0],
    targetState: targetState[0],
    order,
  };
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
  const fields = lifecycleDecodeFieldBatch(
    forest.fields,
    forest.keys,
    `Stored tree ${path} Forest`,
  );
  const roots = fields.get("rootFieldKey");
  assert.equal(roots?.length, 1, `Stored tree ${path} lacks its single root node`);
  const root = roots[0];
  assert.equal(root.type, "org.watershed.shared-tree.handles.Root",
    `Stored tree ${path} has another root schema`);
  const field = (name) => root.fields.get(name) ?? [];
  const label = field("label");
  assert.equal(label.length, 1, `Stored tree ${path} lacks its label`);
  assert.equal(label[0].type, "com.fluidframework.leaf.string",
    `Stored tree ${path} label has another schema`);
  const optional = field("link");
  assert(optional.length <= 1, `Stored tree ${path} has multiple optional handles`);
  assert(optional.every(({ type }) =>
    type === "com.fluidframework.leaf.handle"),
  `Stored tree ${path} optional link is not a handle`);
  const linksNode = field("links");
  assert.equal(linksNode.length, 1, `Stored tree ${path} lacks its links node`);
  assert.equal(linksNode[0].type, "org.watershed.shared-tree.handles.Links",
    `Stored tree ${path} links have another schema`);
  const links = {};
  for (const [name, values] of linksNode[0].fields) {
    assert.equal(values.length, 1,
      `Stored tree ${path} link ${name} lacks its single handle`);
    assert.equal(values[0].type, "com.fluidframework.leaf.handle",
      `Stored tree ${path} link ${name} is not a handle`);
    links[name] = handlePath(values[0].value);
  }
  const sequenceNode = field("sequence");
  assert.equal(sequenceNode.length, 1, `Stored tree ${path} lacks its sequence node`);
  assert.equal(sequenceNode[0].type, "org.watershed.shared-tree.handles.Sequence",
    `Stored tree ${path} sequence has another schema`);
  const sequence = sequenceNode[0].fields.get("") ?? [];
  assert(sequence.every(({ type }) => type === "com.fluidframework.leaf.handle"),
    `Stored tree ${path} sequence contains a non-handle`);
  return {
    label: label[0].value,
    optional: optional[0] === undefined ? null : handlePath(optional[0].value),
    links,
    sequence: sequence.map(({ value }) => handlePath(value)),
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
    gates: [],
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
    let upstreamConfig = config;
    if (section.startsWith("handleReconnect") && writer === "upstream") {
      const endpoint = new URL(config.socketUrl);
      const gate = await DeliveryGate.open(
        endpoint.hostname,
        Number(endpoint.port || 80),
        { documentId: environment.documentId },
      );
      environment.gates.push(gate);
      environment.writerGate = gate;
      upstreamConfig = {
        ...config,
        socketUrl: `http://127.0.0.1:${gate.port}`,
      };
    }
    environment.upstreamSession = await constructors.openSession(
      upstreamConfig,
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
  for (const gate of environment.gates.toReversed()) {
    try {
      await gate.close();
    } catch (error) {
      errors.push(error);
    }
  }
  if (errors.length === 0) return;
  if (originalError) originalError.cleanupErrors = errors;
  else throw new AggregateError(errors, "Lifecycle environment cleanup failed");
}

export async function synchronize(environment) {
  const upstream = [
    environment.creator.container,
    environment.upstreamSession.container,
    environment.peerSession.container,
  ];
  const synchronizedUpstream = (minimumSequenceNumber = 0) => {
    const sequences = upstream.map(({ deltaManager }) =>
      deltaManager.lastSequenceNumber
    );
    return upstream.every((container) =>
      !container.isDirty
        && container.deltaManager.inbound.length === 0
        && container.deltaManager.outbound.length === 0
    ) && sequences.every((sequence) =>
      sequence === sequences[0] && sequence >= minimumSequenceNumber);
  };
  await until(synchronizedUpstream, "lifecycle upstream synchronization");
  const upstreamWatermark =
    environment.creator.container.deltaManager.lastSequenceNumber;
  const nativeReceipts = await Promise.all(environment.natives.map((adapter) =>
    adapter.awaitSynced(upstreamWatermark)));
  const nativeWatermark = nativeReceipts.reduce((maximum, receipt) => {
    assert(Number.isSafeInteger(receipt?.sequenceNumber)
      && receipt.sequenceNumber >= upstreamWatermark,
    "Lifecycle native synchronization lacks a processed watermark");
    return Math.max(maximum, receipt.sequenceNumber);
  }, upstreamWatermark);
  await until(
    () => synchronizedUpstream(nativeWatermark),
    "lifecycle upstream synchronization after native receipts",
  );
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

function validateRetentionLoader(
  name,
  writer,
  continuation,
  rawSnapshot,
  targets,
  summary,
  { requireApplicationProtocol = true } = {},
) {
  const fetched = new Map();
  const allowedFetched = new Set();
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
    const collectBlobIds = (node) => {
      for (const id of Object.values(node.blobs)) allowedFetched.add(id);
      for (const child of Object.values(node.trees)) collectBlobIds(child);
    };
    collectBlobIds(physical);
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
    if (requireApplicationProtocol) {
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
  }
  for (const [id, bytes] of fetched) {
    assert(expectedBlobs[id] !== undefined || allowedFetched.has(id),
      `${name} fresh loader fetched an unrelated blob ${id}`);
    if (expectedBlobs[id] !== undefined) {
      assert.equal(bytes.toString("base64"), expectedBlobs[id],
        `${name} fresh loader fetched bytes differ for ${id}`);
    }
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

function reconnectGate(environment, writer) {
  return writer === "upstream"
    ? environment.writerGate
    : environment.adapters[writer].client.gate;
}

async function reconnectWriterAdapter(environment, writer) {
  if (writer === "upstream") {
    const gate = reconnectGate(environment, writer);
    await gate.disconnect();
    await until(
      () => !environment.upstreamSession.container.connected,
      "upstream gate-owned disconnect",
    );
    await gate.reconnect();
    environment.upstreamSession.container.connect();
    await until(
      () => environment.upstreamSession.container.connected,
      "upstream gate-owned reconnect",
    );
    return;
  }
  await environment.adapters[writer].disconnect();
  await environment.adapters[writer].reconnect();
}

async function authorReconnectUpstream(environment, label) {
  const map = await environment.upstreamSession.data.createMap();
  map.set("value", label);
  environment.upstreamSession.data.view.root.link = map.handle;
  return {
    target: {
      documentId: environment.documentId,
      path: map.handle.absolutePath,
      attributes: attributes(map),
    },
    local: { value: map.get("value") },
    replies: [],
  };
}

async function authorReconnectNative(environment, writer, label) {
  const adapter = environment.adapters[writer];
  const replies = [];
  const command = async (request) => {
    const result = await nativeCommand(adapter, request);
    replies.push({ request, result });
    return result;
  };
  const map = await command({ command: "create-map", name: "reconnect-target" });
  await command({
    command: "shared-map-set",
    name: "reconnect-target",
    key: "value",
    value: label,
  });
  await command({
    command: "set",
    path: ["link"],
    value: taggedHandle(map),
  });
  return {
    target: { path: map.url, attributes: channelAttributes.map },
    local: {
      value: (await adapter.client.sharedMapGet("reconnect-target", "value")).value,
    },
    replies,
  };
}

async function observeReconnectUpstreamPeer(session) {
  const handle = session.data.view.root.link;
  const map = await handle.get();
  return {
    sequenceNumber: session.container.deltaManager.lastSequenceNumber,
    target: {
      path: handle.absolutePath,
      attributes: attributes(map),
    },
    value: map.get("value"),
  };
}

async function observeReconnectNativePeer(adapter) {
  const target = handleValue(await adapter.client.read(["link"]));
  await adapter.client.openMap("reconnect-peer-target", target);
  const checkpoint = await adapter.checkpoint();
  return {
    sequenceNumber: checkpoint.sequenceNumber,
    target: { path: target.url },
    value: (await adapter.client.sharedMapGet(
      "reconnect-peer-target",
      "value",
    )).value,
    pendingTreeCount: checkpoint.pendingTreeCount,
    inflightSubmissionCount: checkpoint.inflightSubmissionCount,
  };
}

function reconnectLogicalCommits(checkpoint) {
  return (checkpoint.history?.pending ?? []).map((commit) => ({
    revision: commit.revision,
    originatorId: commit.originatorId,
    changeset: jsonClone(commit.changeset),
    payload: decodeReconnectPayload(
      commit.changeset.payload ?? commit.changeset.raw,
    ),
  }));
}

function reconnectAcceptedSubmissions(messages, clientIds) {
  return decodeTreeSubmissions(messages)
    .filter(({ clientId }) => clientIds.includes(clientId))
    .map((submission) => ({
      outerSequenceNumber: submission.outerSequenceNumber,
      clientSequenceNumber: submission.clientSequenceNumber,
      referenceSequenceNumber: submission.referenceSequenceNumber,
      allocations: jsonClone(submission.allocations),
      commits: submission.commits.map((commit) => ({
        innerIndex: commit.innerIndex,
        revision: commit.revision,
        originatorId: commit.originatorId,
        changeset: jsonClone(commit.changeset),
        payload: decodeReconnectPayload(commit.changeset),
      })),
    }));
}

async function runReconnectWindow(config, context, writer, id) {
  const environment = await createEnvironment(
    config,
    context.runId,
    `handleReconnect-${id}`,
    writer,
    context.constructors,
  );
  let failure;
  try {
    const label = `handleReconnect-${id}-${writer}-${context.runId.slice(0, 8)}`;
    const writerAdapter = writer === "upstream"
      ? upstreamAdapter(environment.upstreamSession)
      : environment.adapters[writer];
    const gate = reconnectGate(environment, writer);
    const historyBefore = await serverHistory(environment.creator);
    const baseline = await writerAdapter.checkpoint();
    const gateBaseline = gate.evidence();
    const heldOffset = gateBaseline.held.length;
    const outboundOffset = gateBaseline.outboundOccurrences.length;
    if (id === "before-service-acceptance") {
      gate.hold("outbound", "op");
    } else {
      gate.hold("inbound", "op");
    }
    const authored = writer === "upstream"
      ? await authorReconnectUpstream(environment, label)
      : await authorReconnectNative(environment, writer, label);
    const pending = await writerAdapter.checkpoint();
    let acceptedBeforeDisconnect = [];
    if (id === "before-service-acceptance") {
      await until(() => gate.evidence().held.slice(heldOffset)
        .some(({ direction, kind }) =>
          direction === "outbound" && kind === "op"),
      `${writer} reconnect held original outbound batch`);
      acceptedBeforeDisconnect = (await serverHistory(environment.creator))
        .slice(historyBefore.length)
        .filter(({ type, clientId }) =>
          type === "op" && clientId === baseline.clientId);
      assert.equal(acceptedBeforeDisconnect.length, 0,
        `${writer} reconnect preaccept edit reached service history`);
    } else {
      await until(async () => (await serverHistory(environment.creator))
        .slice(historyBefore.length)
        .some(({ type, clientId }) =>
          type === "op" && clientId === baseline.clientId),
      `${writer} reconnect service acceptance`);
      acceptedBeforeDisconnect = (await serverHistory(environment.creator))
        .slice(historyBefore.length)
        .filter(({ type, clientId }) =>
          type === "op" && clientId === baseline.clientId);
      const acceptedSequences = acceptedBeforeDisconnect
        .map(({ sequenceNumber }) => sequenceNumber);
      await until(() => {
        const held = gate.evidence().held
          .filter(({ direction, kind }) => direction === "inbound" && kind === "op")
          .flatMap(({ sequenceNumbers }) => sequenceNumbers);
        return acceptedSequences.every((sequenceNumber) =>
          held.includes(sequenceNumber));
      }, `${writer} reconnect held accepted acknowledgement`);
    }
    const gateBeforeDisconnect = gate.evidence();
    await reconnectWriterAdapter(environment, writer);
    await writerAdapter.awaitSynced();
    await synchronize(environment);
    const final = await writerAdapter.checkpoint();
    final.connected = writerAdapter.isConnected();
    const history = await serverHistory(environment.creator);
    const clientIds = writer === "upstream"
      ? [...writerAdapter.clientIds]
      : [...environment.adapters[writer].clientIds];
    const sequenced = deltaEvidence(
      history.slice(historyBefore.length)
        .filter(({ type, clientId }) =>
          type === "op" && clientIds.includes(clientId)),
    );
    const peers = {
      upstream: await observeReconnectUpstreamPeer(environment.peerSession),
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
        peers[target] = await observeReconnectNativePeer(peer);
      } finally {
        await peer?.close();
      }
    }
    const gateEvidence = gate.evidence();
    const submitted = gateEvidence.outboundOccurrences
      .slice(outboundOffset)
      .map(({ id: occurrenceId, connectionId, hash: occurrenceHash,
        sequenceNumbers, byteLength, submissions }) => ({
        id: occurrenceId,
        connectionId,
        hash: occurrenceHash,
        sequenceNumbers,
        byteLength,
        submissions: jsonClone(submissions),
      }));
    const targets = { target: authored.target };
    return {
      id,
      documentId: environment.documentId,
      label,
      target: authored.target,
      local: authored.local,
      nativeReplies: authored.replies,
      writerClientIds: clientIds,
      baseline,
      pending,
      final,
      logical: {
        original: reconnectLogicalCommits(pending),
        accepted: reconnectAcceptedSubmissions(sequenced, clientIds),
      },
      raw: {
        submitted,
        sequenced,
        dependencies: dependencyEvidence(sequenced, targets),
        acceptedBeforeDisconnect: deltaEvidence(acceptedBeforeDisconnect),
        gateBeforeDisconnect,
        gate: gateEvidence,
      },
      peer: {
        expectedImplementations: requiredPeerImplementations(writer),
        observations: peers,
      },
    };
  } catch (error) {
    failure = error;
    throw error;
  } finally {
    await closeEnvironment(environment, failure);
  }
}

async function createScheduleTarget(environment, writer, plan) {
  const value = `schedule-value-${plan.id}`;
  if (writer === "upstream") {
    const map = await environment.upstreamSession.data.createMap();
    map.set("self", map.handle);
    return {
      value,
      target: {
        documentId: environment.documentId,
        path: map.handle.absolutePath,
        attributes: attributes(map),
      },
      attach(key) {
        environment.upstreamSession.data.view.root.links.set(key, map.handle);
      },
      cleanup(key) {
        environment.upstreamSession.data.view.root.links.delete(key);
      },
      writeValue() {
        map.set("value", value);
      },
      localValue() {
        return map.get("value");
      },
    };
  }
  const adapter = environment.adapters[writer];
  const name = `schedule-${plan.index}`;
  const target = await nativeCommand(adapter, {
    command: "create-map",
    name,
  });
  await nativeCommand(adapter, {
    command: "shared-map-set",
    name,
    key: "self",
    value: target,
  });
  return {
    value,
    target: {
      documentId: environment.documentId,
      path: target.url,
      attributes: channelAttributes.map,
    },
    async attach(key) {
      await nativeCommand(adapter, {
        command: "map-set",
        path: ["links"],
        key,
        value: taggedHandle(target),
      });
    },
    async cleanup(key) {
      await nativeCommand(adapter, {
        command: "map-delete",
        path: ["links"],
        key,
      });
    },
    async writeValue() {
      await nativeCommand(adapter, {
        command: "shared-map-set",
        name,
        key: "value",
        value,
      });
    },
    async localValue() {
      return (await adapter.client.sharedMapGet(name, "value")).value;
    },
  };
}

async function observeScheduleTarget(environment, observer, plan, target, value) {
  const upstreamHandle =
    environment.peerSession.data.view.root.links.get(plan.id);
  assert(upstreamHandle, `${plan.id} upstream peer lacks the target handle`);
  const upstreamMap = await upstreamHandle.get();
  const observedHandle = handleValue(
    await observer.client.mapGet(["links"], plan.id),
  );
  await observer.client.openMap(`schedule-peer-${plan.index}`, observedHandle);
  const observedValue = (await observer.client.sharedMapGet(
    `schedule-peer-${plan.index}`,
    "value",
  )).value;
  assert.equal(upstreamHandle.absolutePath, target.path,
    `${plan.id} upstream peer resolved another target`);
  assert.equal(observedHandle.url, target.path,
    `${plan.id} native peer resolved another target`);
  assert.equal(upstreamMap.get("value"), value,
    `${plan.id} upstream peer read another value`);
  assert.equal(observedValue, value,
    `${plan.id} native peer read another value`);
  const peerClientId = environment.peerSession.container.clientId;
  const peerProcessedSequenceNumber =
    environment.peerSession.container.deltaManager.lastSequenceNumber;
  const peerTransport = environment.peerSession.transportEvidence();
  return {
    target: observedHandle.url,
    value: observedValue,
    native: {
      instanceId: observer.instanceId,
      clientIds: [...observer.clientIds],
      target: observedHandle.url,
      value: observedValue,
    },
    upstream: {
      instanceId: peerClientId,
      clientIds: [peerClientId],
      processedSequenceNumber: peerProcessedSequenceNumber,
      observation: {
        clientId: peerClientId,
        lastSequenceNumber: peerProcessedSequenceNumber,
      },
      transport: {
        connections: peerTransport.connections,
      },
      target: upstreamHandle.absolutePath,
      value: upstreamMap.get("value"),
    },
  };
}

async function openScheduleTarget(adapter, plan) {
  const handle = handleValue(await adapter.client.mapGet(
    ["links"],
    `${plan.id}:stage`,
  ));
  const name = `schedule-author-${plan.index}`;
  await adapter.client.openMap(name, handle);
  return {
    adapter,
    name,
    target: handle.url,
    async write(value) {
      await nativeCommand(adapter, {
        command: "shared-map-set",
        name,
        key: "value",
        value,
      });
    },
  };
}

async function resetScheduleGate(gate, direction, id) {
  try {
    await gate.release(direction);
  } catch (error) {
    assert.match(error.message, /dropped while disconnected/,
      `${id} delivery gate reset failed`);
  }
}

async function disconnectScheduleActor(environment, actor, plan) {
  if (actor.name === "writer" && plan.writer === "upstream") {
    await actor.gate.disconnect();
    await until(
      () => !environment.upstreamSession.container.connected,
      `${plan.id} upstream schedule disconnect`,
    );
  } else {
    await actor.adapter.disconnect();
  }
}

async function reconnectScheduleActor(environment, actor, plan) {
  if (actor.name === "writer" && plan.writer === "upstream") {
    await actor.gate.reconnect();
    environment.upstreamSession.container.connect();
    await until(
      () => environment.upstreamSession.container.connected,
      `${plan.id} upstream schedule reconnect`,
    );
    await actor.adapter.checkpoint();
  } else {
    await actor.adapter.reconnect();
  }
}

async function runLifecycleSchedule(environment, scheduler, observer, plan) {
  const writerAdapter = environment.scheduleWriterAdapter;
  const writerGate = reconnectGate(environment, plan.writer);
  const writerGateBefore = writerGate.evidence();
  const historyBefore = await serverHistory(environment.creator);
  const target = await createScheduleTarget(environment, plan.writer, plan);
  const stageKey = `${plan.id}:stage`;
  await target.attach(stageKey);
  await writerAdapter.awaitSynced();
  await scheduler.awaitSynced();
  let targetAuthor;
  await until(async () => {
    try {
      targetAuthor = await openScheduleTarget(scheduler, plan);
      return true;
    } catch {
      return false;
    }
  }, `${plan.id} scheduler target load`);
  assert.equal(targetAuthor.target, target.target.path,
    `${plan.id} target author resolved another map`);
  const writerActor = {
    name: "writer",
    adapter: writerAdapter,
    gate: writerGate,
  };
  const targetActor = {
    name: "target",
    adapter: scheduler,
    gate: scheduler.client.gate,
  };
  const disconnectMode = plan.mode === "disconnect-before-acceptance"
    || plan.mode === "disconnect-after-acceptance";
  const actors = disconnectMode ? [writerActor] : [writerActor, targetActor];
  const operationActors = {
    "parent-reference": writerActor,
    "target-state": disconnectMode ? writerActor : targetActor,
  };
  const operationRuns = {
    "parent-reference": () => target.attach(plan.id),
    "target-state": () => disconnectMode
      ? target.writeValue()
      : targetAuthor.write(target.value),
  };
  const gateBefore = Object.fromEntries(
    actors.map((actor) => [
      actor.name,
      actor.name === "writer" ? writerGateBefore : actor.gate.evidence(),
    ]),
  );
  const direction = plan.mode === "outbound-held"
      || plan.mode === "disconnect-before-acceptance"
    ? "outbound"
    : plan.mode === "inbound-held"
        || plan.mode === "disconnect-after-acceptance"
      ? "inbound"
      : undefined;
  if (direction) {
    for (const actor of actors) actor.gate.hold(direction, "op");
  }
  const issueOrder = plan.operationOrder === "target-first"
    ? ["target-state", "parent-reference"]
    : ["parent-reference", "target-state"];
  for (const operation of issueOrder) {
    const actor = operationActors[operation];
    await operationRuns[operation]();
    await new Promise((resolve) => setImmediate(resolve));
    if (direction === undefined) await actor.adapter.awaitSynced();
  }
  const releaseActors = plan.releaseOrder === "reverse"
    ? issueOrder.toReversed().map((operation) => operationActors[operation])
    : issueOrder.map((operation) => operationActors[operation]);
  const uniqueReleaseActors = [...new Map(
    releaseActors.map((actor) => [actor.name, actor]),
  ).values()];
  const held = (actor, heldDirection) =>
    actor.gate.evidence().held
      .slice(gateBefore[actor.name].held.length)
      .filter(({ direction: candidate, kind }) =>
        candidate === heldDirection && kind === "op");
  const heldReady = (actor, heldDirection) => {
    const entries = held(actor, heldDirection);
    const messages = heldDirection === "outbound"
      ? scheduleOutboundMessages(entries)
      : scheduleInboundMessages(entries);
    const requireBoth = heldDirection === "inbound";
    const parentReady = !requireBoth && actor.name !== "writer"
      || scheduleHandleReferences(messages).some(({ key, path }) =>
        key === plan.id && path === target.target.path);
    const targetReady = !requireBoth
        && actor.name !== "target" && !disconnectMode
      || scheduleMapSets(messages, target.target.path)
        .some(({ key, value }) => key === "value" && value === target.value);
    return parentReady && targetReady;
  };
  if (plan.operationOrder === "target-first") {
    assert.equal(issueOrder[0], "target-state");
  }
  if (plan.mode === "outbound-held") {
    await until(() => actors.every((actor) =>
      heldReady(actor, "outbound")), `${plan.id} outbound holds`);
    for (const actor of releaseActors) {
      await actor.gate.release("outbound");
      await actor.adapter.awaitSynced();
    }
  } else if (plan.mode === "disconnect-before-acceptance") {
    await until(() => actors.every((actor) =>
      heldReady(actor, "outbound")), `${plan.id} preaccept holds`);
    for (const actor of actors) {
      await disconnectScheduleActor(environment, actor, plan);
    }
    for (const actor of uniqueReleaseActors) {
      await reconnectScheduleActor(environment, actor, plan);
      if (actor.name === "writer" && plan.writer === "upstream") {
        await resetScheduleGate(actor.gate, "outbound", plan.id);
      }
    }
  } else if (plan.mode === "inbound-held"
    || plan.mode === "disconnect-after-acceptance") {
    await until(() => actors.every((actor) =>
      heldReady(actor, "inbound")), `${plan.id} inbound holds`);
    if (plan.mode === "disconnect-after-acceptance") {
      for (const actor of actors) {
        await disconnectScheduleActor(environment, actor, plan);
      }
      for (const actor of uniqueReleaseActors) {
        await reconnectScheduleActor(environment, actor, plan);
        if (actor.name === "writer" && plan.writer === "upstream") {
          await resetScheduleGate(actor.gate, "inbound", plan.id);
        }
      }
    } else {
      for (const actor of releaseActors) await actor.gate.release("inbound");
    }
  }
  await writerAdapter.awaitSynced();
  const schedulerObservation = await scheduler.awaitSynced();
  await target.cleanup(stageKey);
  const writerSync = await writerAdapter.awaitSynced();
  await synchronize(environment);
  const writerObservation = plan.writer === "upstream"
    ? await writerAdapter.checkpoint()
    : {
      implementation: plan.writer,
      instanceId: writerAdapter.instanceId,
      sequenceNumber: writerSync.sequenceNumber,
      pendingTreeCount: writerSync.observation.pendingTreeCount,
      inflightSubmissionCount: writerSync.observation.inFlightCount,
      clientId: writerSync.observation.clientId,
      observation: writerSync.observation,
      readError: null,
    };
  const localValue = await target.localValue();
  assert.equal(localValue, target.value, `${plan.id} local target value changed`);
  const history = await serverHistory(environment.creator);
  const sequenced = deltaEvidence(
    history.slice(historyBefore.length)
      .filter(({ type, clientId }) =>
        type === "op" && actors.some((actor) => actor.adapter.clientIds.has(clientId))),
  );
  const dependencies = dependencyEvidence(sequenced, {
    target: target.target,
  });
  const operations = scheduleOperationEvidence(
    sequenced,
    plan,
    target.target,
    target.value,
  );
  const accepted = operations.parentReference.message;
  const throughSequenceNumber = Math.max(
    ...operations.sequenced.map(({ sequenceNumber }) => sequenceNumber),
  );
  const peer = await observeScheduleTarget(
    environment,
    observer,
    plan,
    target.target,
    target.value,
  );
  const observerObservation = await observer.awaitSynced(throughSequenceNumber);
  const actorDelivery = Object.fromEntries(actors.map((actor) => {
    const before = gateBefore[actor.name];
    const after = actor.gate.evidence();
    const held = after.held.slice(before.held.length);
    const heldConnections = new Set(held.map(({ connectionId }) => connectionId));
    return [actor.name, {
      instanceId: actor.adapter.instanceId,
      clientIds: [...actor.adapter.clientIds],
      observation: actor.name === "writer"
        ? jsonClone(writerObservation)
        : jsonClone(schedulerObservation),
      held,
      controls: after.controls.slice(before.controls.length),
      delivered: after.delivered.slice(before.delivered.length),
      handshakes: after.handshakes.slice(before.handshakes.length),
      connections: after.connections.slice(before.connections.length),
      submitted: after.outboundOccurrences.slice(before.outboundOccurrences.length),
      ...(disconnectMode ? {
        preWindow: {
          connections: before.connections.filter(({ connectionId }) =>
            heldConnections.has(connectionId)),
          handshakes: before.handshakes.filter(({ connectionId }) =>
            heldConnections.has(connectionId)),
        },
      } : {}),
      errorsBefore: before.errors.length,
      errorsAfter: after.errors.length,
    }];
  }));
  const submitted = Object.values(actorDelivery)
    .flatMap(({ submitted: occurrences }) => occurrences);
  assert(submissionMessages(submitted).some((message) =>
    operationIdentityKey(message) === operationIdentityKey(accepted)),
  `${plan.id} accepted operation differs from actual outbound identity`);
  return {
    id: plan.id,
    index: plan.index,
    writer: plan.writer,
    seed: lifecycleScheduleSeed,
    target: target.target,
    local: {
      value: localValue,
      handlePath: target.target.path,
      writerInstanceId: writerAdapter.instanceId,
      writerClientIds: [...writerAdapter.clientIds],
      writerObservation,
    },
    delivery: {
      mode: plan.mode,
      releaseOrder: plan.releaseOrder,
      operationOrder: plan.operationOrder,
      issueOrder,
      releaseActors: uniqueReleaseActors.map(({ name }) => name),
      actors: actorDelivery,
      held: Object.entries(actorDelivery)
        .flatMap(([actor, evidence]) =>
          evidence.held.map((item) => ({ actor, ...item }))),
      controls: Object.entries(actorDelivery)
        .flatMap(([actor, evidence]) =>
          evidence.controls.map((item) => ({ actor, ...item }))),
      delivered: Object.entries(actorDelivery)
        .flatMap(([actor, evidence]) =>
          evidence.delivered.map((item) => ({ actor, ...item }))),
      handshakes: Object.entries(actorDelivery)
        .flatMap(([actor, evidence]) =>
          evidence.handshakes.map((item) => ({ actor, ...item }))),
      connections: Object.entries(actorDelivery)
        .flatMap(([actor, evidence]) =>
          evidence.connections.map((item) => ({ actor, ...item }))),
      submitted,
      errorsBefore: Object.values(actorDelivery)
        .reduce((sum, evidence) => sum + evidence.errorsBefore, 0),
      errorsAfter: Object.values(actorDelivery)
        .reduce((sum, evidence) => sum + evidence.errorsAfter, 0),
    },
    accepted,
    dependencies,
    operations,
    peer,
    observer: {
      implementation: observer.implementation,
      instanceId: observer.instanceId,
      acceptedSequenceNumber: throughSequenceNumber,
      processedSequenceNumber: observerObservation.sequenceNumber,
      observation: observerObservation.observation,
    },
    skipped: false,
    actualHandleWork: true,
    divergence: false,
  };
}

async function runLifecycleSchedules(config, context) {
  const plans = lifecycleSchedulePlans();
  const records = [];
  const observers = [];
  for (const writer of writers) {
    const writerPlans = plans.filter((candidate) => candidate.writer === writer);
    for (let offset = 0; offset < writerPlans.length;
      offset += lifecycleScheduleBatchSize) {
      const batch = writerPlans.slice(offset, offset + lifecycleScheduleBatchSize);
      const environment = await createEnvironment(
        config,
        context.runId,
        "handleReconnectSchedules",
        writer,
        context.constructors,
      );
      let failure;
      try {
        environment.scheduleWriterAdapter = writer === "upstream"
          ? upstreamAdapter(environment.upstreamSession)
          : environment.adapters[writer];
        const observerImplementation = writer === "javascript"
          ? "erlang"
          : "javascript";
        const scheduler = await openNativePeer(
          environment,
          config,
          observerImplementation,
          context.constructors,
        );
        environment.natives.push(scheduler);
        const observer = await openNativePeer(
          environment,
          config,
          observerImplementation,
          context.constructors,
        );
        environment.natives.push(observer);
        for (const plan of batch) {
          try {
            records.push(await runLifecycleSchedule(
              environment,
              scheduler,
              observer,
              plan,
            ));
          } catch (error) {
            error.message = `${plan.id}: ${error.message}`;
            throw error;
          }
        }
        const synchronized = await observer.awaitSynced();
        observers.push({
          writer,
          batch: offset / lifecycleScheduleBatchSize,
          implementation: observerImplementation,
          instanceId: observer.instanceId,
          clientIds: [...observer.clientIds],
          processedSequenceNumber: synchronized.sequenceNumber,
          observation: synchronized.observation,
          transport: observer.evidence(),
        });
      } catch (error) {
        failure = error;
        throw error;
      } finally {
        await closeEnvironment(environment, failure);
      }
    }
  }
  records.sort((left, right) => left.index - right.index);
  const section = {
    name: "handleSchedules",
    formatVersion: 1,
    runId: context.runId,
    contract,
    skipped: false,
    seed: lifecycleScheduleSeed,
    requested: lifecycleScheduleCount,
    expectedIds: plans.map(({ id }) => id),
    records,
    observers,
    artifacts: [],
  };
  const relative = "handleSchedules/schedules.json";
  const artifact = {
    ...section,
    artifacts: undefined,
  };
  const bytes = `${JSON.stringify(artifact)}\n`;
  await mkdir(join(context.output, "handleSchedules"), { recursive: true });
  await writeFile(join(context.output, relative), bytes, { mode: 0o600 });
  context.artifacts.files[relative] = { sha256: hash(bytes) };
  section.artifacts.push({ path: relative, sha256: hash(bytes) });
  return section;
}

async function authorMatrixUpstream(environment, label) {
  const data = environment.upstreamSession.data;
  const document = await createUpstreamTree(data, `${label}-document`);
  const sameMap = await data.createMap();
  const sameTree = await createUpstreamTree(data, `${label}-same-tree`);
  sameMap.set("value", `${label}-same-map`);
  sameMap.set("self", sameMap.handle);
  sameMap.set("tree", sameTree.tree.handle);
  sameTree.view.root.link = sameMap.handle;
  data.bootstrap.set("matrix-document", document.tree.handle);
  document.view.root.link = sameMap.handle;
  document.view.root.links.set("map", sameMap.handle);
  document.view.root.links.set("tree", sameTree.tree.handle);
  document.view.root.sequence.insertAtEnd(sameMap.handle, sameTree.tree.handle);
  await synchronize(environment);
  return {
    document: document.tree,
    documentView: document.view,
    map: sameMap,
    tree: sameTree.tree,
    treeView: sameTree.view,
    secondary: undefined,
    receipts: [],
    async cross() {
      const secondary = await createUpstreamDataStore(environment.upstreamSession);
      const map = await secondary.createMap();
      const tree = await createUpstreamTree(secondary, `${label}-cross-tree`);
      map.set("value", `${label}-cross-map`);
      map.set("self", map.handle);
      map.set("tree", tree.tree.handle);
      tree.view.root.link = map.handle;
      secondary.root.set("map", map.handle);
      secondary.root.set("tree", tree.tree.handle);
      data.bootstrap.set("matrix-secondary", secondary.handle);
      document.view.root.link = map.handle;
      document.view.root.links.set("map", map.handle);
      document.view.root.links.set("tree", tree.tree.handle);
      document.view.root.sequence.removeRange();
      document.view.root.sequence.insertAtEnd(map.handle, tree.tree.handle);
      await synchronize(environment);
      this.secondary = secondary;
      this.map = map;
      this.treeView.dispose();
      this.tree = tree.tree;
      this.treeView = tree.view;
    },
    async undoRedo() {
      const watch = watchRetention(document.view);
      watch.captureNext();
      document.view.root.link = sameMap.handle;
      await synchronize(environment);
      const undo = watch.retained();
      const insertion = RevertibleStatus[undo.status];
      watch.captureNext();
      undo.revert(true);
      await synchronize(environment);
      const redo = watch.retained();
      const undone = RevertibleStatus[redo.status];
      redo.revert(true);
      await synchronize(environment);
      this.receipts.push({
        insertion,
        undone,
        events: structuredClone(watch.events),
        finalLink: document.view.root.link.absolutePath,
      });
      watch.off();
    },
    targets() {
      return {
        document: {
          path: document.tree.handle.absolutePath,
          attributes: attributes(document.tree),
        },
        map: { path: this.map.handle.absolutePath, attributes: attributes(this.map) },
        tree: { path: this.tree.handle.absolutePath, attributes: attributes(this.tree) },
        ...(this.secondary === undefined ? {} : {
          secondary: {
            path: this.secondary.handle.absolutePath,
            attributes: attributes(this.secondary.root),
          },
        }),
      };
    },
  };
}

async function authorMatrixNative(environment, writer, label) {
  const adapter = environment.adapters[writer];
  const replies = [];
  const command = async (request) => {
    const result = await nativeCommand(adapter, request);
    replies.push({ request, result });
    return result;
  };
  await command({ command: "root-map", name: "matrix-root" });
  const document = await command({
    command: "create-tree",
    name: "matrix-document",
    schema: handleStoredSchema,
    view: handleStoredSchema,
    initialRoot: taggedHandleRoot(`${label}-document`),
  });
  const sameMap = await command({ command: "create-map", name: "matrix-same-map" });
  const sameTree = await command({
    command: "create-tree",
    name: "matrix-same-tree",
    schema: handleStoredSchema,
    view: handleStoredSchema,
    initialRoot: taggedHandleRoot(`${label}-same-tree`),
  });
  await command({
    command: "shared-map-set", name: "matrix-same-map",
    key: "value", value: `${label}-same-map`,
  });
  await command({
    command: "shared-map-set", name: "matrix-same-map", key: "self", value: sameMap,
  });
  await command({
    command: "shared-map-set", name: "matrix-same-map", key: "tree", value: sameTree,
  });
  await command({
    command: "set", tree: "matrix-same-tree",
    path: ["link"], value: taggedHandle(sameMap),
  });
  await command({
    command: "shared-map-set", name: "matrix-root",
    key: "matrix-document", value: document,
  });
  await command({
    command: "set", tree: "matrix-document",
    path: ["link"], value: taggedHandle(sameMap),
  });
  for (const [key, value] of [["map", sameMap], ["tree", sameTree]]) {
    await command({
      command: "map-set", tree: "matrix-document",
      path: ["links"], key, value: taggedHandle(value),
    });
  }
  await command({
    command: "array-insert", tree: "matrix-document",
    path: ["sequence"], index: 0,
    values: [taggedHandle(sameMap), taggedHandle(sameTree)],
  });
  await synchronize(environment);
  return {
    adapter,
    command,
    document,
    map: sameMap,
    tree: sameTree,
    secondary: undefined,
    receipts: replies,
    async cross() {
      await command({ command: "create-data-store", name: "matrix-secondary-store" });
      const secondary = await command({
        command: "data-store-root",
        store: "matrix-secondary-store",
        name: "matrix-secondary-root",
      });
      const map = await command({
        command: "create-map",
        store: "matrix-secondary-store",
        name: "matrix-cross-map",
      });
      const tree = await command({
        command: "create-tree",
        store: "matrix-secondary-store",
        name: "matrix-cross-tree",
        schema: handleStoredSchema,
        view: handleStoredSchema,
        initialRoot: taggedHandleRoot(`${label}-cross-tree`),
      });
      await command({
        command: "shared-map-set", name: "matrix-cross-map",
        key: "value", value: `${label}-cross-map`,
      });
      await command({
        command: "shared-map-set", name: "matrix-cross-map", key: "self", value: map,
      });
      await command({
        command: "shared-map-set", name: "matrix-cross-map", key: "tree", value: tree,
      });
      await command({
        command: "set", tree: "matrix-cross-tree",
        path: ["link"], value: taggedHandle(map),
      });
      await command({
        command: "shared-map-set", name: "matrix-secondary-root", key: "map", value: map,
      });
      await command({
        command: "shared-map-set", name: "matrix-secondary-root", key: "tree", value: tree,
      });
      await command({
        command: "shared-map-set", name: "matrix-root",
        key: "matrix-secondary", value: secondary,
      });
      await command({
        command: "set", tree: "matrix-document",
        path: ["link"], value: taggedHandle(map),
      });
      for (const [key, value] of [["map", map], ["tree", tree]]) {
        await command({
          command: "map-set", tree: "matrix-document",
          path: ["links"], key, value: taggedHandle(value),
        });
      }
      await command({
        command: "array-remove", tree: "matrix-document",
        path: ["sequence"], start: 0, end: 2,
      });
      await command({
        command: "array-insert", tree: "matrix-document",
        path: ["sequence"], index: 0,
        values: [taggedHandle(map), taggedHandle(tree)],
      });
      await synchronize(environment);
      this.secondary = secondary;
      this.map = map;
      this.tree = tree;
    },
    async undoRedo() {
      await command({ command: "subscribe", tree: "matrix-document" });
      await command({
        command: "set", tree: "matrix-document",
        path: ["link"], value: taggedHandle(sameMap),
      });
      const insertion = await command({
        op: "retainLastLocalCommit",
        tree: "matrix-document",
        name: "matrix-undo",
      });
      await command({
        op: "revert", tree: "matrix-document",
        name: "matrix-undo", dispose: true,
      });
      const redo = await command({
        op: "retainLastLocalCommit",
        tree: "matrix-document",
        name: "matrix-redo",
      });
      await command({
        op: "revert", tree: "matrix-document",
        name: "matrix-redo", dispose: true,
      });
      await synchronize(environment);
      this.receipts.push({
        insertion,
        redo,
        checkpoint: await command({
          command: "checkpoint", tree: "matrix-document",
        }),
      });
    },
    targets() {
      return {
        document: { path: document.url, attributes: channelAttributes.tree },
        map: { path: this.map.url, attributes: channelAttributes.map },
        tree: { path: this.tree.url, attributes: channelAttributes.tree },
        ...(this.secondary === undefined ? {} : {
          secondary: {
            path: this.secondary.url,
            attributes: channelAttributes.map,
          },
        }),
      };
    },
  };
}

function matrixSnapshotEvidence(rawSnapshot, targets) {
  return {
    ...snapshotEvidence(rawSnapshot, targets),
    gc: snapshotGc(rawSnapshot),
    components: snapshotComponents(rawSnapshot),
    metadata: snapshotMetadata(rawSnapshot),
    factories: Object.fromEntries(Object.entries(targets).map(
      ([name, target]) => [name, snapshotFactory(rawSnapshot, target.path)],
    )),
  };
}

async function publishMatrixCheckpoint(
  config,
  environment,
  writer,
  authored,
  checkpoint,
) {
  await synchronize(environment);
  const publication = writer === "upstream"
    ? await publishUpstreamSummary(
      config,
      environment.containers,
      environment.documentId,
      `Task 8 handleReloadMatrix:${writer}:${checkpoint}`,
      { store: handleServiceStore },
    )
    : await environment.adapters[writer].summarizePublication();
  await synchronize(environment);
  const stored = await fetchSnapshot(environment.creator);
  const targets = authored.targets();
  const uploads = writer === "upstream" ? undefined
    : environment.adapters[writer].evidence().http.filter(({ method, path, status }) =>
      method === "POST" && status === 201 && /\/git\/(?:blobs|trees)\/?$/.test(path));
  const summary = writer === "upstream"
    ? summaryEntryEvidence(publication.summaryTree)
    : submittedSummaryEvidence(uploads, stored.raw.tree.trees[".app"].id);
  return {
    id: checkpoint,
    writer,
    publication: {
      ...publicationEvidence(writer, publication),
      ...(uploads === undefined ? {} : { uploads }),
    },
    snapshot: {
      version: stored.version,
      treeSha256: stored.treeSha256,
      blobs: stored.blobs,
      evidence: matrixSnapshotEvidence(stored.raw, targets),
    },
    targets,
    summary,
    sequenced: deltaEvidence(await serverHistory(environment.creator)),
    rawSnapshot: stored.raw,
    undoRedo: structuredClone(authored.receipts),
  };
}

async function observeMatrixUpstream(session, cell, targets) {
  const documentHandle = session.data.bootstrap.get("matrix-document");
  const document = await documentHandle.get();
  const view = document.viewWith(handleTreeConfig);
  const mapHandle = view.root.links.get("map");
  const treeHandle = view.root.links.get("tree");
  const map = await mapHandle.get();
  const tree = await treeHandle.get();
  const treeView = tree.viewWith(handleTreeConfig);
  const observed = {
    document: documentHandle.absolutePath,
    map: mapHandle.absolutePath,
    tree: treeHandle.absolutePath,
    mapValue: map.get("value"),
    mapTree: map.get("tree").absolutePath,
    treeMap: treeView.root.link.absolutePath,
    treeLabel: treeView.root.label,
    continuation: map.get(`continuation:${cell}`),
    continuations: [...map.entries()]
      .filter(([key]) => key.startsWith("continuation:"))
      .sort(([left], [right]) => left.localeCompare(right)),
  };
  treeView.dispose();
  view.dispose();
  assert.equal(observed.document, targets.document.path);
  assert.equal(observed.map, targets.map.path);
  assert.equal(observed.tree, targets.tree.path);
  return observed;
}

async function observeMatrixNative(adapter, cell, targets) {
  const suffix = hash(cell).slice(0, 8);
  await nativeCommand(adapter, {
    command: "root-map", name: `matrix-observer-root-${suffix}`,
  });
  const document = (await nativeCommand(adapter, {
    command: "shared-map-get",
    name: `matrix-observer-root-${suffix}`,
    key: "matrix-document",
  })).value;
  await nativeCommand(adapter, {
    command: "open-tree",
    name: `matrix-observer-document-${suffix}`,
    handle: document,
    view: handleStoredSchema,
  });
  const map = handleValue(await adapter.client.read(
    ["links", "map"],
    `matrix-observer-document-${suffix}`,
  ));
  const tree = handleValue(await adapter.client.read(
    ["links", "tree"],
    `matrix-observer-document-${suffix}`,
  ));
  await adapter.client.openMap(`matrix-observer-map-${suffix}`, map);
  await adapter.client.openTree(
    `matrix-observer-tree-${suffix}`,
    tree,
    handleStoredSchema,
  );
  const entries = await adapter.client.sharedMapEntries(
    `matrix-observer-map-${suffix}`,
  );
  return {
    document: document.url,
    map: map.url,
    tree: tree.url,
    mapValue: (await adapter.client.sharedMapGet(
      `matrix-observer-map-${suffix}`,
      "value",
    )).value,
    mapTree: (await adapter.client.sharedMapGet(
      `matrix-observer-map-${suffix}`,
      "tree",
    )).value.url,
    treeMap: handleValue(await adapter.client.read(
      ["link"],
      `matrix-observer-tree-${suffix}`,
    )).url,
    treeLabel: (await adapter.client.read(
      ["label"],
      `matrix-observer-tree-${suffix}`,
    )).value.value,
    continuation: (await adapter.client.sharedMapGet(
      `matrix-observer-map-${suffix}`,
      `continuation:${cell}`,
    )).value,
    continuations: entries
      .filter(([key]) => key.startsWith("continuation:"))
      .sort(([left], [right]) => left.localeCompare(right)),
  };
}

async function matrixFreshReader(
  config,
  context,
  environment,
  writer,
  checkpoint,
  reader,
  publication,
  expectedBefore,
) {
  const cell = `${writer}:${checkpoint}:${reader}`;
  const continuationValue = `${cell}:${context.runId.slice(0, 8)}`;
  const treeLabel = `${checkpoint}:${reader}:${context.runId.slice(0, 8)}`;
  if (reader === "upstream") {
    const fresh = await context.constructors.openSession(
      config,
      environment.containers,
      environment.documentId,
      false,
      { store: handleServiceStore, cache: false, observeStorage: true },
    );
    let peer;
    try {
      const before = await observeMatrixUpstream(fresh, cell, publication.targets);
      assert.deepEqual(before, expectedBefore);
      const document = await fresh.data.bootstrap.get("matrix-document").get();
      const view = document.viewWith(handleTreeConfig);
      const map = await view.root.links.get("map").get();
      const tree = await view.root.links.get("tree").get();
      const treeView = tree.viewWith(handleTreeConfig);
      const historyBefore = (await serverHistory(environment.creator)).length;
      map.set(`continuation:${cell}`, continuationValue);
      treeView.root.label = treeLabel;
      await synchronize(environment);
      peer = await openNativePeer(
        environment,
        config,
        "javascript",
        context.constructors,
      );
      const loader = upstreamLoaderEvidence(fresh.storageObservations);
      const sequenced = deltaEvidence(
        (await serverHistory(environment.creator)).slice(historyBefore),
      );
      const throughSequenceNumber = Math.max(
        ...sequenced.filter(({ type }) => type === "op")
          .map(({ sequenceNumber }) => sequenceNumber),
      );
      const peerSync = await peer.awaitSynced(throughSequenceNumber);
      const observed = await observeMatrixNative(peer, cell, publication.targets);
      const result = {
        id: cell,
        writer,
        checkpoint,
        reader,
        freshIdentity: {
          instanceId: fresh.container.clientId,
          clientIds: [fresh.container.clientId],
        },
        loadedVersion: loader.selectedVersion,
        loader,
        storage: structuredClone(fresh.storageObservations),
        transport: fresh.transportEvidence(),
        before,
        expectedBefore,
        resolved: {
          document: document.handle.absolutePath,
          map: map.handle.absolutePath,
          tree: tree.handle.absolutePath,
          mapTree: map.get("tree").absolutePath,
          treeMap: treeView.root.link.absolutePath,
        },
        continuation: {
          key: `continuation:${cell}`,
          value: continuationValue,
          treeLabel,
          sequenced,
          peer: {
            implementation: "javascript",
            observed: true,
            receipt: {
              instanceId: peer.instanceId,
              clientIds: [...peer.clientIds],
              readBeforeClose: true,
              processedSequenceNumber: peerSync.sequenceNumber,
              observation: peerSync.observation,
              transport: peer.evidence(),
              continuation: observed.continuation,
              treeLabel: observed.treeLabel,
            },
            state: observed,
          },
        },
      };
      treeView.dispose();
      view.dispose();
      return result;
    } finally {
      await peer?.close();
      fresh.container.dispose();
    }
  }
  const fresh = await context.constructors.nativeAdapter(reader, config, {
    runId: context.runId,
    documentId: environment.documentId,
    tenant: config.tenantId,
    viewSchema: JSON.stringify(handleStoredSchema),
  }, environment.jwt);
  environment.natives.push(fresh);
  try {
    await fresh.awaitSynced();
    const before = await observeMatrixNative(fresh, cell, publication.targets);
    assert.deepEqual(before, expectedBefore);
    const suffix = hash(cell).slice(0, 8);
    const historyBefore = (await serverHistory(environment.creator)).length;
    await fresh.client.sharedMapSet(
      `matrix-observer-map-${suffix}`,
      `continuation:${cell}`,
      continuationValue,
    );
    await nativeCommand(fresh, {
      command: "set",
      tree: `matrix-observer-tree-${suffix}`,
      path: ["label"],
      value: { kind: "string", value: treeLabel },
    });
    await synchronize(environment);
    const transport = fresh.evidence();
    const loader = nativeLoaderEvidence(transport);
    const sequenced = deltaEvidence(
      (await serverHistory(environment.creator)).slice(historyBefore),
    );
    const throughSequenceNumber = Math.max(
      ...sequenced.filter(({ type }) => type === "op")
        .map(({ sequenceNumber }) => sequenceNumber),
    );
    await until(() =>
      environment.peerSession.container.deltaManager.lastSequenceNumber
        >= throughSequenceNumber,
    `${cell} upstream observer processed continuation`);
    const peerProcessedSequenceNumber =
      environment.peerSession.container.deltaManager.lastSequenceNumber;
    const peerTransport = environment.peerSession.transportEvidence();
    const observed = await observeMatrixUpstream(
      environment.peerSession,
      cell,
      publication.targets,
    );
    return {
      id: cell,
      writer,
      checkpoint,
      reader,
      freshIdentity: {
        instanceId: fresh.instanceId,
        clientIds: [...fresh.clientIds],
      },
      loadedVersion: loader.selectedVersion,
      loader,
      transport,
      before,
      expectedBefore,
      resolved: {
        document: before.document,
        map: before.map,
        tree: before.tree,
        mapTree: before.mapTree,
        treeMap: before.treeMap,
      },
      continuation: {
        key: `continuation:${cell}`,
        value: continuationValue,
        treeLabel,
        sequenced,
        peer: {
          implementation: "upstream",
          observed: true,
          receipt: {
            instanceId: environment.peerSession.container.clientId,
            clientIds: [environment.peerSession.container.clientId],
            readBeforeClose: true,
            processedSequenceNumber: peerProcessedSequenceNumber,
            observation: {
              clientId: environment.peerSession.container.clientId,
              lastSequenceNumber: peerProcessedSequenceNumber,
            },
            transport: peerTransport,
            continuation: observed.continuation,
            treeLabel: observed.treeLabel,
          },
          state: observed,
        },
      },
    };
  } finally {
    await fresh.close();
    environment.natives = environment.natives.filter(
      (candidate) => candidate !== fresh,
    );
  }
}

async function runReloadMatrixWriter(config, context, writer) {
  const environment = await createEnvironment(
    config,
    context.runId,
    "handleReloadMatrix",
    writer,
    context.constructors,
  );
  let failure;
  try {
    const label = `handleReloadMatrix-${writer}-${context.runId.slice(0, 8)}`;
    const authored = writer === "upstream"
      ? await authorMatrixUpstream(environment, label)
      : await authorMatrixNative(environment, writer, label);
    const checkpoints = [];
    const cells = [];
    for (const checkpoint of matrixCheckpoints) {
      if (checkpoint === "cross-datastore") await authored.cross();
      if (checkpoint === "handle-undo-redo") await authored.undoRedo();
      const publication = await publishMatrixCheckpoint(
        config,
        environment,
        writer,
        authored,
        checkpoint,
      );
      const firstExpected = writer === "upstream"
        ? await observeMatrixUpstream(
          environment.peerSession,
          `${writer}:${checkpoint}:upstream`,
          publication.targets,
        )
        : await observeMatrixUpstream(
          environment.peerSession,
          `${writer}:${checkpoint}:upstream`,
          publication.targets,
        );
      let expectedBefore = firstExpected;
      for (const reader of writers) {
        const cell = await matrixFreshReader(
          config,
          context,
          environment,
          writer,
          checkpoint,
          reader,
          publication,
          expectedBefore,
        );
        cells.push(cell);
        expectedBefore = {
          ...cell.continuation.peer.state,
          continuation: undefined,
        };
      }
      checkpoints.push(publication);
    }
    return { writer, checkpoints, cells };
  } catch (error) {
    failure = error;
    throw error;
  } finally {
    await closeEnvironment(environment, failure);
  }
}

async function runReloadMatrix(config, context) {
  const rows = [];
  const cells = [];
  for (const writer of writers) {
    const produced = await runReloadMatrixWriter(config, context, writer);
    rows.push({ writer, checkpoints: produced.checkpoints, artifacts: [] });
    cells.push(...produced.cells);
  }
  const artifact = {
    formatVersion: 1,
    runId: context.runId,
    section: "handleReloadMatrix",
    contract,
    rows,
    cells,
  };
  const relative = "handleReloadMatrix/matrix.json";
  const bytes = `${JSON.stringify(artifact)}\n`;
  await mkdir(join(context.output, "handleReloadMatrix"), { recursive: true });
  await writeFile(join(context.output, relative), bytes, { mode: 0o600 });
  context.artifacts.files[relative] = { sha256: hash(bytes) };
  return {
    name: "handleReloadMatrix",
    runId: context.runId,
    contract,
    skipped: false,
    selection: { kind: "all" },
    expectedCells: matrixCellIds,
    rows: rows.map((row) => ({
      ...row,
      checkpoints: row.checkpoints.map(({ rawSnapshot, ...checkpoint }) =>
        jsonClone(checkpoint)),
      artifacts: [{ path: relative, sha256: hash(bytes) }],
    })),
    cells: jsonClone(cells),
  };
}

async function runReconnectRow(config, context, writer) {
  const windows = [];
  for (const id of [
    "before-service-acceptance",
    "accepted-before-local-ack",
  ]) {
    windows.push(await runReconnectWindow(config, context, writer, id));
  }
  const row = {
    formatVersion: 1,
    runId: context.runId,
    writer,
    contract,
    factory: handleServiceStore.type,
    reconnect: { windows },
    artifacts: [],
  };
  const artifact = {
    formatVersion: 1,
    runId: context.runId,
    section: "handleReconnect",
    writer,
    contract,
    reconnect: { windows },
  };
  const relative = `handleReconnect/${writer}.json`;
  const bytes = `${JSON.stringify(artifact)}\n`;
  await mkdir(join(context.output, "handleReconnect"), { recursive: true });
  await writeFile(join(context.output, relative), bytes, { mode: 0o600 });
  context.artifacts.files[relative] = { sha256: hash(bytes) };
  row.artifacts.push({ path: relative, sha256: hash(bytes) });
  return row;
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
  if (section === "handleReconnect") {
    return runReconnectRow(config, context, writer);
  }
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

function reconnectSubmittedLogical(occurrence) {
  return decodeTreeSubmissions(submissionMessages([occurrence]))
    .flatMap(({ commits }) => commits.map((commit) => ({
      revision: commit.revision,
      originatorId: commit.originatorId,
      changeset: jsonClone(commit.changeset),
      payload: decodeReconnectPayload(commit.changeset),
    })));
}

function reconnectOccurrenceMessage(occurrence, label) {
  assert.equal(occurrence.submissions.length, 1,
    `${label} transport occurrence has another submission count`);
  const submission = occurrence.submissions[0];
  const messages = submission.messageBatches.flat();
  assert.equal(messages.length, 1,
    `${label} transport occurrence has another message count`);
  assert(typeof submission.clientId === "string" && submission.clientId.length > 0,
    `${label} transport occurrence lacks a client`);
  assert(typeof occurrence.connectionId === "string"
    && occurrence.connectionId.length > 0,
  `${label} transport occurrence lacks a connection`);
  assert(/^[a-f0-9]{64}$/.test(occurrence.hash),
    `${label} transport occurrence lacks an exact byte hash`);
  assert(Number.isSafeInteger(occurrence.byteLength) && occurrence.byteLength > 0,
    `${label} transport occurrence lacks an exact byte length`);
  return { ...messages[0], clientId: submission.clientId };
}

function gateOccurrenceIdentity(value) {
  return {
    id: value.id,
    connectionId: value.connectionId,
    hash: value.hash,
    byteLength: value.byteLength,
  };
}

function assertGateOccurrence(label, occurrence, evidence, collection) {
  const copies = evidence[collection].filter(({ id }) => id === occurrence.id);
  assert.equal(copies.length, 1,
    `${label} delivery ${collection} receipt is missing`);
  assert.deepEqual(
    gateOccurrenceIdentity(copies[0]),
    gateOccurrenceIdentity(occurrence),
    `${label} delivery ${collection} receipt differs from its occurrence`,
  );
  if (occurrence.submissions !== undefined) {
    assert.deepEqual(
      copies[0].submissions,
      occurrence.submissions,
      `${label} gate submission differs from its projected payload`,
    );
    if (copies[0].event === "submitOp" && copies[0].topic === undefined) {
      assert.equal(copies[0].submissions.length, 1,
        `${label} exact upstream wire has another submission count`);
      const submission = copies[0].submissions[0];
      const bytes = Buffer.from(
        `42${JSON.stringify([
          "submitOp",
          submission.clientId,
          submission.messageBatches,
        ])}`,
      );
      assert.equal(copies[0].hash, hash(bytes),
        `${label} exact upstream wire hash differs`);
      assert.equal(copies[0].byteLength, bytes.length,
        `${label} exact upstream wire length differs`);
    }
  }
  return copies[0];
}

function reconnectAttachment(message, target, label) {
  const contents = parse(message.contents);
  const routes = attachmentRoutes(contents)
    .filter(({ path }) => path === target.path);
  assert.equal(routes.length, 1,
    `${label} accepted attachment names another target`);
  const targetId = target.path.split("/").filter(Boolean).at(-1);
  const matches = matchingObjects(contents, (value) =>
    value.type === "attach"
      && (value.content ?? value.contents)?.id === targetId);
  assert.equal(matches.length, 1,
    `${label} accepted attachment content is missing or duplicated`);
  const attachment = matches[0].content ?? matches[0].contents;
  assert.equal(attachment.type, channelAttributes.map.type,
    `${label} accepted attachment has another channel type`);
  const entries = attachment.snapshot?.entries;
  assert(Array.isArray(entries),
    `${label} accepted attachment lacks snapshot entries`);
  const blob = (path) => {
    const entry = entries.find((candidate) =>
      candidate.path === path && candidate.type === "Blob");
    assert.equal(entry?.value?.encoding, "utf-8",
      `${label} accepted attachment lacks ${path} UTF-8 content`);
    return JSON.parse(entry.value.contents);
  };
  const attributesValue = blob(".attributes");
  assert.deepEqual(attributesValue, target.attributes,
    `${label} accepted attachment attributes differ`);
  const header = blob("header");
  const value = header?.content?.value;
  assert.equal(value?.type, "Plain",
    `${label} accepted attachment value has another encoding`);
  return {
    path: target.path,
    attributes: attributesValue,
    value: value.value,
  };
}

function metadataWithoutBatchId(metadata) {
  if (metadata === undefined) return undefined;
  const { batchId: _batchId, ...rest } = metadata;
  return rest;
}

function batchWithoutRetryMetadata(contents) {
  const copy = jsonClone(parse(contents));
  for (const value of matchingObjects(copy, (candidate) =>
    candidate.metadata?.batchId !== undefined)) {
    delete value.metadata.batchId;
  }
  return copy;
}

function batchIds(message) {
  return [
    message.metadata?.batchId,
    ...matchingObjects(parse(message.contents), (candidate) =>
      candidate.metadata?.batchId !== undefined)
      .map(({ metadata }) => metadata.batchId),
  ].filter((value) => value !== undefined);
}

async function validateReconnectRow(name, row, artifacts) {
  assert.equal(row.formatVersion, 1, `${name} row format changed`);
  assert.equal(row.runId, artifacts.runId, `${name} row run identity changed`);
  validateContract(row.contract, `${name} row`);
  assert.equal(row.factory, handleServiceStore.type,
    `${name} primary factory differs from the pinned contract`);
  const windows = row.reconnect?.windows;
  assert.deepEqual(
    windows?.map(({ id }) => id),
    ["before-service-acceptance", "accepted-before-local-ack"],
    `${name} disconnect windows differ`,
  );
  assert.equal(new Set(windows.map(({ documentId }) => documentId)).size, 2,
    `${name} reconnect windows must own separate documents`);
  for (const window of windows) {
    const label = `${name}:${row.writer}:${window.id}`;
    assert.equal(window.local.value, window.label,
      `${label} local target edit differs`);
    assert.deepEqual(window.target.attributes, channelAttributes.map,
      `${label} target attributes differ`);
    assert.equal(window.pending.pendingTreeCount, 1,
      `${label} must have exactly one pending logical edit`);
    assert.equal(window.logical.original.length, 1,
      `${label} lacks one original logical batch`);
    const acceptedProjection = reconnectAcceptedSubmissions(
      window.raw.sequenced,
      window.writerClientIds,
    );
    assert.deepEqual(window.logical.accepted, acceptedProjection,
      `${label} accepted logical projection differs from the service delta`);
    assert.equal(acceptedProjection.length, 1,
      `${label} service accepted another target submission count`);
    assert.equal(acceptedProjection[0].commits.length, 1,
      `${label} service accepted another logical edit count`);
    const accepted = acceptedProjection[0];
    assert(Number.isSafeInteger(accepted.outerSequenceNumber)
      && accepted.outerSequenceNumber > 0,
    `${label} lacks an actual server sequence`);
    assert(Number.isSafeInteger(accepted.clientSequenceNumber)
      && accepted.clientSequenceNumber > 0,
    `${label} lacks an outer client sequence`);
    assert(Number.isSafeInteger(accepted.commits[0].innerIndex)
      && accepted.commits[0].innerIndex >= 0,
    `${label} lacks an inner batch position`);
    assert.equal(
      accepted.commits[0].originatorId,
      window.logical.original[0].originatorId,
      `${label} accepted originator differs from the original`,
    );
    assert.deepEqual(
      accepted.commits[0].payload,
      window.logical.original[0].payload,
      `${label} accepted logical payload differs from the original`,
    );
    assert.equal(window.final.pendingTreeCount, 0,
      `${label} pending tree work did not drain`);
    assert.equal(window.final.inflightSubmissionCount, 0,
      `${label} in-flight work did not drain`);
    assert.deepEqual(window.final.history?.pending, [],
      `${label} final pending history did not drain`);
    assert.equal(window.final.connected, true,
      `${label} final writer connection is not active`);
    if (row.writer !== "upstream") {
      assert.equal(window.final.connection?.phase, "ready",
        `${label} final native connection is not ready`);
      assert.equal(window.final.connection?.synced, true,
        `${label} native finalization did not synchronize`);
      assert.equal(window.final.connection?.pendingTreeCount, 0,
        `${label} native finalization retained pending tree work`);
      assert.equal(window.final.connection?.inFlightCount, 0,
        `${label} native finalization retained in-flight work`);
      assert.equal(window.final.connection?.clientId, window.final.clientId,
        `${label} native final connection names another client`);
    }
    assert(window.final.sequenceNumber >= accepted.outerSequenceNumber,
      `${label} final acknowledgement precedes service acceptance`);
    const derived = dependencyEvidence(
      window.raw.sequenced,
      { target: window.target },
    );
    assert.deepEqual(window.raw.dependencies, derived,
      `${label} compressor allocation or target dependency evidence differs`);
    assert(derived.allocations.length > 0,
      `${label} lacks compressor allocation evidence`);
    const target = derived.targets.find(({ target: id }) => id === "target");
    assert(target, `${label} lacks target path evidence`);
    assert.equal(
      target.occurrences.filter(({ kind }) => kind === "attach").length,
      1,
      `${label} target attachment is missing or duplicated`,
    );
    assert.equal(
      target.occurrences.filter(({ kind }) => kind === "reference").length,
      1,
      `${label} target reference is missing or duplicated`,
    );
    assert.equal(derived.commits.length, 1,
      `${label} logical tree edit is missing or duplicated`);
    const connections = new Set(window.raw.gate.connections.map(
      ({ connectionId }) => connectionId,
    ));
    const dataOccurrences = [];
    const noopOccurrences = [];
    for (const occurrence of window.raw.submitted) {
      assert(connections.has(occurrence.connectionId),
        `${label} accepted connection is missing for transport occurrence`);
      assertGateOccurrence(
        label,
        occurrence,
        window.raw.gate,
        "outboundOccurrences",
      );
      const message = reconnectOccurrenceMessage(occurrence, label);
      if (message.type === "noop") {
        assert.equal(message.contents, undefined,
          `${label} SDK noop has operation contents`);
        assert.equal(message.metadata, undefined,
          `${label} SDK noop has operation metadata`);
        assert(Number.isSafeInteger(message.clientSequenceNumber)
          && message.clientSequenceNumber > accepted.clientSequenceNumber,
        `${label} SDK noop has another client sequence`);
        assert(Number.isSafeInteger(message.referenceSequenceNumber)
          && message.referenceSequenceNumber >= accepted.outerSequenceNumber,
        `${label} SDK noop has another reference sequence`);
        assert(window.writerClientIds.includes(message.clientId),
          `${label} SDK noop names another writer client`);
        assertGateOccurrence(label, occurrence, window.raw.gate, "delivered");
        noopOccurrences.push({ occurrence, message });
        continue;
      }
      assert.equal(message.type, "op",
        `${label} transport occurrence classification is unsupported`);
      const logical = reconnectSubmittedLogical(occurrence);
      assert.equal(logical.length, 1,
        `${label} target data occurrence has another logical edit count`);
      dataOccurrences.push({ occurrence, message, logical });
    }
    const expectedDataOccurrenceCount =
      window.id === "before-service-acceptance" ? 2 : 1;
    assert.equal(dataOccurrences.length, expectedDataOccurrenceCount,
      `${label} original/resubmitted target data count differs`);
    assert.equal(
      dataOccurrences.length + noopOccurrences.length,
      window.raw.submitted.length,
      `${label} transport occurrence classification is incomplete`,
    );
    const originalOccurrence = dataOccurrences[0];
    const acceptedOccurrence = dataOccurrences.at(-1);
    const originalLogical = originalOccurrence.logical;
    const acceptedLogical = acceptedOccurrence.logical;
    assert.equal(originalLogical.length, 1,
      `${label} original outbound logical edit count differs`);
    assert.equal(
      originalLogical[0].originatorId,
      window.logical.original[0].originatorId,
      `${label} original outbound originator differs`,
    );
    assert.deepEqual(
      originalLogical[0].payload,
      window.logical.original[0].payload,
      `${label} original outbound logical payload differs`,
    );
    assert.deepEqual(acceptedLogical, originalLogical,
      `${label} resubmitted logical identity differs`);
    assert.deepEqual(
      batchWithoutRetryMetadata(acceptedOccurrence.message.contents),
      batchWithoutRetryMetadata(originalOccurrence.message.contents),
      `${label} resubmitted batch differs from the complete original batch`,
    );
    assert.deepEqual(
      metadataWithoutBatchId(acceptedOccurrence.message.metadata),
      metadataWithoutBatchId(originalOccurrence.message.metadata),
      `${label} resubmitted batch metadata differs`,
    );
    if (window.id === "before-service-acceptance") {
      assert.notEqual(
        acceptedOccurrence.occurrence.connectionId,
        originalOccurrence.occurrence.connectionId,
        `${label} retry reused the dropped connection`,
      );
      assert.notEqual(
        acceptedOccurrence.message.clientId,
        originalOccurrence.message.clientId,
        `${label} retry reused the dropped client`,
      );
      assert.equal(
        acceptedOccurrence.message.clientSequenceNumber,
        originalOccurrence.message.clientSequenceNumber,
        `${label} retry changed its client sequence`,
      );
      assert(
        acceptedOccurrence.message.referenceSequenceNumber
          > originalOccurrence.message.referenceSequenceNumber,
        `${label} retry did not advance its reference sequence`,
      );
      const originalBatchId = originalOccurrence.message.metadata?.batchId;
      const retryBatchId = acceptedOccurrence.message.metadata?.batchId;
      const expectedBatchId = originalBatchId
        ?? `${originalOccurrence.message.clientId}_[${
          originalOccurrence.message.clientSequenceNumber
        }]`;
      assert.equal(
        retryBatchId,
        expectedBatchId,
        `${label} retry batch identity differs`,
      );
      assert(batchIds(acceptedOccurrence.message).every(
        (batchId) => batchId === expectedBatchId,
      ), `${label} retry inner batch identity differs`);
      assert(batchIds(originalOccurrence.message).every(
        (batchId) => batchId === expectedBatchId,
      ), `${label} original inner batch identity differs`);
    }
    const acceptedOutbound = submissionMessages([
      acceptedOccurrence.occurrence,
    ])
      .map(transportOperationIdentity);
    const acceptedServiceMessages = window.raw.sequenced
      .filter(({ type, clientId }) =>
        type === "op" && window.writerClientIds.includes(clientId));
    assert.equal(acceptedServiceMessages.length, 1,
      `${label} service delta has another target operation count`);
    assert.deepEqual(
      acceptedOutbound,
      acceptedServiceMessages.map(transportOperationIdentity),
      `${label} accepted outbound batch differs from the service delta`);
    const attachment = reconnectAttachment(
      acceptedServiceMessages[0],
      window.target,
      label,
    );
    assert.equal(window.label, attachment.value,
      `${label} label differs from accepted attachment content`);
    assert.equal(window.local.value, attachment.value,
      `${label} local value differs from accepted attachment content`);
    const controls = window.raw.gate.controls;
    const holdDirection =
      window.id === "before-service-acceptance" ? "outbound" : "inbound";
    const holdIndex = controls.findIndex(({ action, direction, kind }) =>
      action === "hold" && direction === holdDirection && kind === "op");
    const disconnectIndex = controls.findIndex(({ action }) =>
      action === "disconnect");
    const reconnectIndex = controls.findIndex(({ action }) =>
      action === "reconnect");
    assert(holdIndex >= 0, `${label} delivery gate hold record is missing`);
    assert(disconnectIndex > holdIndex,
      `${label} delivery gate disconnected before the hold`);
    assert(reconnectIndex > disconnectIndex,
      `${label} delivery gate reconnected before disconnect`);
    const disconnect = controls[disconnectIndex];
    assert(disconnect, `${label} delivery gate disconnect record is missing`);
    const acceptedConnection = acceptedOccurrence.occurrence.connectionId;
    assert(window.raw.gate.handshakes.some(({ connectionId }) =>
      connectionId === acceptedConnection),
    `${label} accepted reconnect handshake is missing`);
    assertGateOccurrence(
      label,
      acceptedOccurrence.occurrence,
      window.raw.gate,
      "delivered",
    );
    if (window.id === "before-service-acceptance") {
      assert.equal(window.raw.acceptedBeforeDisconnect.length, 0,
        `${label} falsely claims no service acceptance`);
      const originalId = originalOccurrence.occurrence.id;
      assertGateOccurrence(
        label,
        originalOccurrence.occurrence,
        window.raw.gateBeforeDisconnect,
        "held",
      );
      assert(!window.raw.gateBeforeDisconnect.delivered.some(({ id }) =>
        id === originalId),
      `${label} original batch was delivered before disconnect`);
      assert(disconnect.dropped.outbound.includes(originalId),
        `${label} original batch was not dropped by disconnect`);
      const acceptedDelivery = window.raw.gate.delivered.find(({ direction,
        sequenceNumbers, connectionId }) =>
        direction === "inbound"
          && connectionId === acceptedConnection
          && sequenceNumbers.includes(accepted.outerSequenceNumber));
      assert(acceptedDelivery,
        `${label} accepted service delivery receipt is missing`);
      assert(
        acceptedDelivery.topic === window.documentId
          || acceptedDelivery.topic?.endsWith(`:${window.documentId}`),
        `${label} accepted service delivery names another document`,
      );
    } else {
      assert.deepEqual(
        window.raw.acceptedBeforeDisconnect,
        acceptedServiceMessages,
        `${label} predisconnect acceptance differs from the accepted service identity`,
      );
      assert(window.pending.sequenceNumber < accepted.outerSequenceNumber
        && window.pending.history?.pending?.length === 1,
      `${label} local acknowledgement occurred before the inbound drop`);
      const heldInbound = window.raw.gateBeforeDisconnect.held.filter(
        ({ direction, kind, connectionId, topic }) =>
          direction === "inbound"
            && kind === "op"
            && connectionId === acceptedConnection
            && (topic === window.documentId
              || topic?.endsWith(`:${window.documentId}`)),
      );
      assert(heldInbound.some(({ sequenceNumbers }) =>
        sequenceNumbers.includes(accepted.outerSequenceNumber)),
      `${label} accepted acknowledgement was not held before disconnect`);
      assert(heldInbound.some(({ id }) => disconnect.dropped.inbound.includes(id)),
        `${label} accepted acknowledgement was not dropped by disconnect`);
      const heldIds = new Set(heldInbound.map(({ id }) => id));
      assert(!window.raw.gateBeforeDisconnect.delivered.some(({ id }) =>
        heldIds.has(id)),
      `${label} held accepted echo was delivered before disconnect`);
      assert(!window.raw.gate.delivered.some(({ id }) => heldIds.has(id)),
        `${label} dropped acknowledgement also claims delivery`);
    }
    const expectedPeers = requiredPeerImplementations(row.writer);
    assert.deepEqual(
      [...window.peer.expectedImplementations].sort(),
      [...expectedPeers].sort(),
      `${label} peer implementation policy differs`,
    );
    assert.deepEqual(
      Object.keys(window.peer.observations).sort(),
      [...expectedPeers].sort(),
      `${label} peer implementation coverage differs`,
    );
    for (const [implementation, peer] of Object.entries(
      window.peer.observations,
    )) {
      assert.equal(peer.target.path, window.target.path,
        `${label} ${implementation} resolved another target path`);
      assert.equal(peer.value, attachment.value,
        `${label} ${implementation} differs from accepted attachment content`);
      assert(peer.sequenceNumber >= accepted.outerSequenceNumber,
        `${label} ${implementation} data precedes the accepted receipt`);
      if (implementation !== "upstream") {
        assert.equal(peer.pendingTreeCount, 0,
          `${label} ${implementation} peer has pending tree work`);
        assert.equal(peer.inflightSubmissionCount, 0,
          `${label} ${implementation} peer has in-flight work`);
      }
    }
  }
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
  validateContract(artifact.contract, `${name} artifact`);
  assert.deepEqual(artifact.reconnect, jsonClone(row.reconnect),
    `${name} report reconnect evidence differs from its persisted artifact`);
}

function matrixRequiredBlobIds(raw, targets) {
  const document = snapshotNode(raw, targets.document.path);
  const map = snapshotNode(raw, targets.map.path);
  const tree = snapshotNode(raw, targets.tree.path);
  return [
    document.blobs[".attributes"],
    document.trees.indexes.trees.Forest.blobs.contents,
    document.trees.indexes.trees.Schema.blobs.SchemaString,
    document.trees.indexes.trees.EditManager.blobs.String,
    map.blobs[".attributes"],
    map.blobs.header,
    tree.blobs[".attributes"],
    tree.trees.indexes.trees.Forest.blobs.contents,
    tree.trees.indexes.trees.Schema.blobs.SchemaString,
    tree.trees.indexes.trees.EditManager.blobs.String,
  ];
}

function validateMatrixLoader(name, reader, cell, checkpoint) {
  validateRetentionLoader(name, reader, cell, checkpoint.rawSnapshot, {
    document: checkpoint.targets.document,
    target: checkpoint.targets.map,
  }, checkpoint.summary, {
    requireApplicationProtocol: checkpoint.writer !== "upstream",
  });
  const fetched = new Set(cell.loader.fetchedBlobs.map(({ id }) => id));
  for (const id of matrixRequiredBlobIds(
    checkpoint.rawSnapshot,
    checkpoint.targets,
  )) {
    assert(fetched.has(id),
      `${name} fresh loader did not read required map/tree schema, Forest, history, or attributes blob ${id}`);
  }
}

function requireGcRoutes(name, gc, from, routes) {
  const actual = new Set(gc.gcNodes[from]?.outboundRoutes ?? []);
  for (const route of routes) {
    assert(actual.has(route), `${name} GC edge ${from} -> ${route} is missing`);
  }
}

function validateMatrixGc(name, checkpoint) {
  const { document, map, tree } = checkpoint.targets;
  const gc = checkpoint.snapshot.evidence.gc;
  requireGcRoutes(name, gc, document.path, [map.path, tree.path]);
  requireGcRoutes(name, gc, map.path, [map.path, tree.path]);
  requireGcRoutes(name, gc, tree.path, [map.path]);
  const primary = `/${document.path.split("/")[1]}`;
  requireGcRoutes(name, gc, "/", [primary]);
  requireGcRoutes(name, gc, primary, [document.path]);
  requireGcRoutes(name, gc, `${primary}/root`, [document.path]);
  if (map.path.split("/")[1] !== document.path.split("/")[1]) {
    const secondary = `/${map.path.split("/")[1]}`;
    requireGcRoutes(name, gc, `${primary}/root`, [`${secondary}/root`]);
    requireGcRoutes(name, gc, secondary, [`${secondary}/root`, map.path, tree.path]);
    requireGcRoutes(name, gc, `${secondary}/root`, [map.path, tree.path]);
  }
}

function validateMatrixStoredTrees(name, checkpoint) {
  for (const target of ["document", "tree"]) {
    const node = snapshotNode(
      checkpoint.rawSnapshot,
      checkpoint.targets[target].path,
    );
    assert.deepEqual(
      decodedBlob(
        checkpoint.rawSnapshot,
        node.trees.indexes.trees.Schema,
        "SchemaString",
      ),
      handleStoredSchema,
      `${name} ${target} stored schema differs`,
    );
    assert.deepEqual(
      decodedBlob(checkpoint.rawSnapshot, node, ".attributes"),
      channelAttributes.tree,
      `${name} ${target} persisted attributes differ`,
    );
    storedTreeGraph(checkpoint.rawSnapshot, checkpoint.targets[target].path);
  }
  const map = snapshotNode(checkpoint.rawSnapshot, checkpoint.targets.map.path);
  assert.deepEqual(
    decodedBlob(checkpoint.rawSnapshot, map, ".attributes"),
    channelAttributes.map,
    `${name} map persisted attributes differ`,
  );
}

function validateMatrixCompressor(name, checkpoint) {
  validateCompressorAllocations(name, {
    writer: checkpoint.writer,
    raw: {
      sequenced: checkpoint.sequenced,
      dependencies: dependencyEvidence(
        checkpoint.sequenced,
        checkpoint.targets,
      ),
    },
  }, checkpoint.rawSnapshot, checkpoint.snapshot.evidence.referenceSequenceNumber);
}

function canonicalSummary(value) {
  if (value?.type !== "tree") return value;
  return {
    type: "tree",
    entries: value.entries
      .map(([entryName, entry]) => [entryName, canonicalSummary(entry)])
      .sort(([left], [right]) => left.localeCompare(right)),
  };
}

function fetchedSummaryEvidence(raw, tree) {
  return {
    type: "tree",
    entries: [
      ...Object.entries(tree.trees ?? {}).map(([entryName, child]) =>
        [entryName, fetchedSummaryEvidence(raw, child)]),
      ...Object.entries(tree.blobs ?? {}).map(([entryName, id]) =>
        [entryName, { type: "blob", base64: raw.blobs[id] }]),
    ],
  };
}

function fetchedApplicationSummaryEvidence(raw) {
  return {
    type: "tree",
    entries: [
      ...Object.entries(raw.tree.trees ?? {})
        .filter(([entryName]) =>
          entryName !== ".app" && entryName !== ".protocol")
        .map(([entryName, child]) =>
          [entryName, fetchedSummaryEvidence(raw, child)]),
      ...Object.entries(raw.tree.blobs ?? {}).map(([entryName, id]) =>
        [entryName, { type: "blob", base64: raw.blobs[id] }]),
    ],
  };
}

function applicationDataSummaryEvidence(summary) {
  return {
    ...summary,
    entries: summary.entries.filter(([entryName]) => entryName !== ".protocol"),
  };
}

function matrixTreeLabels(edit, detail) {
  assert(edit?.version === 7 && edit.changeset?.length === 1,
    `${detail} SharedTree operation has another format`);
  const data = edit.changeset[0].data;
  assert(data?.changes?.length === 1,
    `${detail} SharedTree change lacks its root field`);
  const root = data.changes[0];
  assert(root.fieldKey === "rootFieldKey"
    && root.fieldKind === "ModularEditBuilder.Generic"
    && root.change?.length === 1
    && root.change[0][0] === 0
    && root.change[0][1]?.fieldChanges?.length === 1,
  `${detail} SharedTree label change has another target`);
  const field = root.change[0][1].fieldChanges[0];
  const replacement = field.change?.r;
  if (field.fieldKey !== "label" || field.fieldKind !== "Value"
    || !Number.isSafeInteger(replacement?.s)) return [];
  assert(data.builds?.builds?.length === 1
    && Array.isArray(data.builds.trees?.data),
  `${detail} SharedTree label change lacks its build data`);
  const [mapping] = data.builds.builds[0];
  assert(Array.isArray(mapping),
    `${detail} SharedTree label build mapping changed`);
  const built = mapping.find(([id]) => id === replacement.s);
  assert(built, `${detail} SharedTree label replacement lacks its build`);
  const fields = lifecycleDecodeFieldBatch(
    data.builds.trees,
    data.builds.trees.data.map((_, index) => String(index)),
    `${detail} SharedTree label build`,
  );
  const nodes = fields.get(String(built[1]));
  assert(nodes?.length === 1
    && nodes[0].type === "com.fluidframework.leaf.string"
    && nodes[0].fields.size === 0,
  `${detail} SharedTree label build is not one string`);
  return [nodes[0].value];
}

function matrixContinuationEffects(name, cell, checkpoint) {
  const operations = cell.continuation.sequenced.filter(({ type }) => type === "op");
  assert(operations.length > 0, `${name} continuation lacks an actual operation`);
  const effects = [];
  for (const operation of operations) {
    assert(Number.isSafeInteger(operation.sequenceNumber)
      && operation.sequenceNumber
        > checkpoint.snapshot.evidence.referenceSequenceNumber,
    `${name} continuation operation does not follow the selected snapshot`);
    assert(Number.isSafeInteger(operation.clientSequenceNumber)
      && operation.clientSequenceNumber > 0
      && Number.isSafeInteger(operation.referenceSequenceNumber)
      && operation.referenceSequenceNumber
        >= checkpoint.snapshot.evidence.referenceSequenceNumber
      && cell.freshIdentity.clientIds.includes(operation.clientId),
    `${name} fresh reader operation identity differs`);
    for (const { contents } of operationItems(operation)) {
      if (contents?.type !== "component") continue;
      const datastore = contents.contents;
      const channel = datastore?.contents;
      if (channel?.type !== "op") continue;
      const addressed = channel.content;
      const path = `/${datastore.address}/${addressed?.address}`;
      if (path === checkpoint.targets.map.path) {
        const edit = addressed.contents;
        if (edit?.type === "set" && edit.value?.type === "Plain") {
          effects.push({
            kind: "map-set",
            sequenceNumber: operation.sequenceNumber,
            message: operation,
            target: path,
            key: edit.key,
            value: edit.value.value,
          });
        }
      }
      if (path === checkpoint.targets.tree.path) {
        for (const label of matrixTreeLabels(
          addressed.contents,
          `${name} sequence ${operation.sequenceNumber}`,
        )) {
          effects.push({
            kind: "tree-label",
            sequenceNumber: operation.sequenceNumber,
            message: operation,
            target: path,
            label,
          });
        }
      }
    }
  }
  const map = effects.filter(({ kind, key, value }) =>
    kind === "map-set"
      && key === cell.continuation.key
      && value === cell.continuation.value);
  const tree = effects.filter(({ kind, label }) =>
    kind === "tree-label" && label === cell.continuation.treeLabel);
  assert.equal(map.length, 1,
    `${name} continuation lacks its decoded SharedMap operation`);
  assert.equal(tree.length, 1,
    `${name} continuation lacks its decoded SharedTree operation`);
  return { map: map[0], tree: tree[0], operations };
}

function operationIdentityKey(message) {
  const canonical = (value) => {
    if (Array.isArray(value)) return value.map(canonical);
    if (!value || typeof value !== "object") return value;
    return Object.fromEntries(Object.entries(value)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, item]) => [key, canonical(item)]));
  };
  return hash(canonical(transportOperationIdentity(message)));
}

function validateMatrixFreshTransport(name, cell, effects) {
  const transport = cell.transport;
  assert(transport && Array.isArray(transport.connections)
    && Array.isArray(transport.outboundOccurrences),
  `${name} fresh reader lacks actual connection and submission receipts`);
  const connectionIds = new Set(transport.connections.map(({ connectionId }) =>
    connectionId));
  const effectMessages = new Set(
    [effects.map.message, effects.tree.message].map(operationIdentityKey),
  );
  const matching = transport.outboundOccurrences.filter((occurrence) =>
    submissionMessages([occurrence]).some((message) =>
      effectMessages.has(operationIdentityKey(message))));
  assert.equal(new Set(matching.flatMap((occurrence) =>
    submissionMessages([occurrence])
      .filter((message) => effectMessages.has(operationIdentityKey(message)))
      .map(operationIdentityKey))).size, effectMessages.size,
  `${name} accepted continuation differs from actual fresh-reader submissions`);
  assert(matching.every(({ connectionId }) => connectionIds.has(connectionId)),
    `${name} fresh-reader submission lacks its actual connection`);
  assert(matching.every((occurrence) =>
    submissionMessages([occurrence]).every(({ clientId }) =>
      cell.freshIdentity.clientIds.includes(clientId))),
  `${name} fresh-reader submission used another client identity`);
  if (cell.reader === "upstream") {
    assert.equal(cell.freshIdentity.instanceId,
      cell.freshIdentity.clientIds[0],
    `${name} upstream fresh instance differs from its client`);
    assert(transport.connections.some(({ clientId }) =>
      cell.freshIdentity.clientIds.includes(clientId)),
    `${name} upstream fresh reader lacks its actual connection identity`);
  } else {
    assert.equal(transport.instanceId, cell.freshIdentity.instanceId,
      `${name} native fresh instance differs from its transport identity`);
  }
  return {
    connectionIds: new Set(matching.map(({ connectionId }) => connectionId)),
  };
}

function matrixSequenceReceipts(
  transport,
  connectionIds,
  includeHandshakeMessages = true,
) {
  const receipts = new Map();
  const add = (connectionId, sequenceNumbers) => {
    if (!connectionIds.has(connectionId)) return;
    for (const sequenceNumber of sequenceNumbers ?? []) {
      if (!Number.isSafeInteger(sequenceNumber)) continue;
      const connections = receipts.get(sequenceNumber) ?? new Set();
      connections.add(connectionId);
      receipts.set(sequenceNumber, connections);
    }
  };
  for (const delivery of transport.delivered ?? []) {
    if (delivery.direction === "inbound" && delivery.duplicate !== true) {
      add(delivery.connectionId, delivery.sequenceNumbers);
    }
  }
  if (includeHandshakeMessages) {
    for (const handshake of transport.handshakes ?? []) {
      add(handshake.connectionId, handshake.initialMessageSequenceNumbers);
    }
  }
  return receipts;
}

function matrixSequencedMessageReceipts(
  transport,
  connectionIds,
  includeHandshakeMessages,
) {
  const receipts = new Map();
  const add = (connectionId, messages) => {
    if (!connectionIds.has(connectionId)) return;
    for (const message of messages ?? []) {
      const key = [
        message.sequenceNumber,
        message.type,
        operationIdentityKey(message),
      ].join(":");
      const connections = receipts.get(key) ?? new Set();
      connections.add(connectionId);
      receipts.set(key, connections);
    }
  };
  for (const delivery of transport.delivered ?? []) {
    if (delivery.direction === "inbound" && delivery.duplicate !== true) {
      add(delivery.connectionId, delivery.sequencedMessages);
    }
  }
  if (includeHandshakeMessages) {
    for (const handshake of transport.handshakes ?? []) {
      add(handshake.connectionId, handshake.initialMessages);
    }
  }
  return receipts;
}

function validateMatrixAcknowledgements(name, cell, effects, freshTransport) {
  const messages = new Map();
  for (const message of [effects.map.message, effects.tree.message]) {
    messages.set(operationIdentityKey(message), message);
  }
  assert.equal(
    new Set([...messages.values()].map(({ sequenceNumber }) =>
      sequenceNumber)).size,
    messages.size,
    `${name} distinct continuation messages share an acknowledgement sequence`,
  );
  const nativeTransport = cell.reader === "upstream"
    ? cell.continuation.peer.receipt.transport
    : cell.transport;
  const connectionIds = cell.reader === "upstream"
    ? new Set(nativeTransport.connections.map(({ connectionId }) => connectionId))
    : freshTransport.connectionIds;
  const receipts = matrixSequenceReceipts(
    nativeTransport,
    connectionIds,
    cell.reader === "upstream",
  );
  const messageReceipts = matrixSequencedMessageReceipts(
    nativeTransport,
    connectionIds,
    cell.reader === "upstream",
  );
  for (const message of messages.values()) {
    const { sequenceNumber } = message;
    assert(receipts.has(sequenceNumber),
      `${name} acknowledgement sequence lacks an actual native delivery receipt`);
    assert(messageReceipts.has(
      [sequenceNumber, message.type, operationIdentityKey(message)].join(":"),
    ), `${name} sequenced service message differs from its native delivery identity`);
  }
  if (cell.reader !== "upstream") {
    assert(nativeTransport.handshakes.some(({ connectionId, clientId }) =>
      connectionIds.has(connectionId)
        && cell.freshIdentity.clientIds.includes(clientId)),
    `${name} native fresh client differs from its connection handshake`);
  }
}

function validateMatrixPeerReceipt(name, cell, effects) {
  assert(writers.includes(cell.continuation.peer.implementation)
    && cell.continuation.peer.implementation !== cell.reader,
  `${name} continuation peer implementation is not independent`);
  assert.equal(cell.continuation.peer.observed, true,
    `${name} continuation peer did not observe the write`);
  const receipt = cell.continuation.peer.receipt;
  assert(receipt && receipt.readBeforeClose === true
    && typeof receipt.instanceId === "string"
    && Array.isArray(receipt.clientIds) && receipt.clientIds.length > 0
    && receipt.transport && receipt.observation,
  `${name} continuation peer lacks its actual read identity before close`);
  assert(!receipt.clientIds.some((id) =>
    cell.freshIdentity.clientIds.includes(id)),
  `${name} continuation peer reused the fresh reader identity`);
  const throughSequenceNumber = Math.max(
    effects.map.sequenceNumber,
    effects.tree.sequenceNumber,
  );
  assert(Number.isSafeInteger(receipt.processedSequenceNumber)
    && receipt.processedSequenceNumber >= throughSequenceNumber,
  `${name} continuation peer processed watermark precedes the writes`);
  if (cell.continuation.peer.implementation === "upstream") {
    assert.equal(receipt.instanceId, receipt.observation.clientId,
      `${name} upstream peer identity differs from its processed receipt`);
    assert.equal(
      receipt.processedSequenceNumber,
      receipt.observation.lastSequenceNumber,
      `${name} upstream peer watermark differs from its delta manager`,
    );
    assert(receipt.clientIds.includes(receipt.observation.clientId)
      && receipt.transport.connections.some(({ clientId }) =>
        receipt.clientIds.includes(clientId)),
    `${name} upstream peer identity differs from its actual connection`);
  } else {
    assert.equal(receipt.instanceId, receipt.transport.instanceId,
      `${name} native peer identity differs from its transport receipt`);
    assert.equal(receipt.observation.phase, "ready",
      `${name} native peer observer phase is not ready`);
    assert.equal(receipt.observation.synced, true,
      `${name} native peer observer is not synchronized`);
    assert.equal(receipt.observation.error, null,
      `${name} native peer observer is not error-free`);
    assert.equal(receipt.observation.inFlightCount, 0,
      `${name} native peer observer has in-flight work`);
    assert.equal(receipt.observation.pendingTreeCount, 0,
      `${name} native peer observer has pending tree work`);
    assert(receipt.clientIds.includes(receipt.observation.clientId),
      `${name} native peer identity differs from its processed receipt`);
    const connectionIds = new Set(
      receipt.transport.connections.map(({ connectionId }) => connectionId),
    );
    const receipts = matrixSequenceReceipts(receipt.transport, connectionIds);
    const observedSequences = [
      effects.map.sequenceNumber,
      effects.tree.sequenceNumber,
    ];
    assert(observedSequences.every((sequenceNumber) =>
      receipts.has(sequenceNumber)),
    `${name} native peer lacks actual delivery of both continuation writes`);
    assert(receipt.transport.handshakes.some((handshake) =>
      handshake.clientId === receipt.observation.clientId
        && observedSequences.every((sequenceNumber) =>
          receipts.get(sequenceNumber)?.has(handshake.connectionId))),
    `${name} native peer observer differs from its delivery connection handshake`);
  }
  assert.equal(receipt.continuation, cell.continuation.value,
    `${name} continuation peer read another map value`);
  assert.equal(receipt.treeLabel, cell.continuation.treeLabel,
    `${name} continuation peer read another tree value`);
}

function validateMatrixContinuation(name, cell, checkpoint) {
  const effects = matrixContinuationEffects(name, cell, checkpoint);
  const freshTransport = validateMatrixFreshTransport(name, cell, effects);
  validateMatrixAcknowledgements(name, cell, effects, freshTransport);
  validateMatrixPeerReceipt(name, cell, effects);
  return effects;
}

function matrixStoredBefore(checkpoint) {
  const map = checkpoint.snapshot.evidence.targets.map.graph;
  const tree = checkpoint.snapshot.evidence.targets.tree.graph;
  return {
    document: checkpoint.targets.document.path,
    map: checkpoint.targets.map.path,
    tree: checkpoint.targets.tree.path,
    mapValue: map.value,
    mapTree: map.tree,
    treeMap: tree.optional,
    treeLabel: tree.label,
    continuations: Object.entries(map)
      .filter(([key]) => key.startsWith("continuation:"))
      .sort(([left], [right]) => left.localeCompare(right)),
  };
}

async function validateReloadMatrixSection(section, artifacts) {
  const name = "handleReloadMatrix";
  assert(section && typeof section === "object", `${name} section is missing`);
  assert.equal(section.name, name, `${name} section name changed`);
  assert.equal(section.runId, artifacts.runId, `${name} section run identity changed`);
  validateContract(section.contract, `${name} section`);
  assert.equal(section.skipped, false, `${name} section is skipped`);
  assert.deepEqual(section.selection, { kind: "all" },
    `${name} complete section selection changed`);
  assert.deepEqual(section.expectedCells, matrixCellIds,
    `${name} fixed expected cell IDs changed`);
  assert.deepEqual(section.cells.map(({ id }) => id), matrixCellIds,
    `${name} missing, duplicate, skipped, or reordered cells`);
  assert.equal(new Set(section.cells.map(({ id }) => id)).size, 27,
    `${name} duplicate cell IDs`);
  assert.deepEqual(section.rows.map(({ writer }) => writer), writers,
    `${name} writer coverage changed`);
  const descriptor = section.rows[0]?.artifacts?.[0];
  assert(descriptor, `${name} persisted matrix artifact is missing`);
  assert(section.rows.every((row) =>
    row.artifacts.length === 1
      && row.artifacts[0].path === descriptor.path
      && row.artifacts[0].sha256 === descriptor.sha256),
  `${name} rows do not bind the same matrix artifact`);
  const registered = artifacts.files[descriptor.path];
  assert(registered, `${name} matrix artifact is not registered`);
  assert.equal(registered.sha256, descriptor.sha256,
    `${name} matrix artifact digest changed`);
  const bytes = await readFile(join(artifacts.root, descriptor.path));
  assert.equal(hash(bytes), descriptor.sha256,
    `${name} persisted matrix artifact bytes changed`);
  const artifact = JSON.parse(bytes.toString("utf8"));
  assert.equal(artifact.runId, section.runId,
    `${name} artifact run identity changed`);
  validateContract(artifact.contract, `${name} artifact`);
  assert.deepEqual(artifact.cells, section.cells,
    `${name} report cells differ from persisted artifact`);
  assert.deepEqual(
    artifact.rows.map(({ writer, checkpoints }) => ({
      writer,
      checkpoints: checkpoints.map(({ rawSnapshot, ...checkpoint }) =>
        jsonClone(checkpoint)),
    })),
    section.rows.map(({ writer, checkpoints }) => ({ writer, checkpoints })),
    `${name} report checkpoints differ from persisted artifact`,
  );
  const checkpointById = new Map();
  for (const [rowIndex, row] of section.rows.entries()) {
    assert.deepEqual(row.checkpoints.map(({ id }) => id), matrixCheckpoints,
      `${name} ${row.writer} checkpoint coverage changed`);
    const artifactRow = artifact.rows[rowIndex];
    assert.equal(artifactRow.writer, row.writer,
      `${name} artifact writer order changed`);
    for (const [checkpointIndex, checkpoint] of row.checkpoints.entries()) {
      const raw = artifactRow.checkpoints[checkpointIndex].rawSnapshot;
      assert(raw, `${name} ${row.writer}:${checkpoint.id} lacks fetched storage bytes`);
      assert.equal(checkpoint.writer, row.writer,
        `${name} checkpoint writer changed`);
      assert.equal(checkpoint.publication.version, checkpoint.snapshot.version,
        `${name} publication names another fetched version`);
      assert.equal(checkpoint.snapshot.treeSha256, hash(raw.tree),
        `${name} fetched tree hash differs from actual bytes`);
      assert.deepEqual(
        checkpoint.snapshot.blobs,
        Object.fromEntries(Object.entries(raw.blobs).map(
          ([id, encoded]) => [id, hash(Buffer.from(encoded, "base64"))],
        )),
        `${name} fetched blob hashes differ from actual bytes`,
      );
      const measured = matrixSnapshotEvidence(raw, checkpoint.targets);
      assert.deepEqual(checkpoint.snapshot.evidence, measured,
        `${name} schema, values, handles, order, GC, compressor, or metadata differ`);
      const fullCheckpoint = { ...checkpoint, rawSnapshot: raw };
      validateMatrixStoredTrees(name, fullCheckpoint);
      validateMatrixGc(name, fullCheckpoint);
      validateMatrixCompressor(name, fullCheckpoint);
      if (row.writer !== "upstream") {
        const uploaded = submittedSummaryEvidence(
          checkpoint.publication.uploads,
          raw.tree.trees[".app"].id,
        );
        assert.deepEqual(checkpoint.summary, uploaded,
          `${name} submitted summary differs from actual native uploads`,
        );
        assert.deepEqual(
          canonicalSummary(applicationDataSummaryEvidence(uploaded)),
          canonicalSummary(fetchedApplicationSummaryEvidence(raw)),
          `${name} uploaded publication differs from fetched stored bytes`,
        );
      }
      assert.equal(measured.compressor.formatVersion, 2,
        `${name} compressor format changed`);
      assert.equal(
        measured.metadata.documentSchema?.info?.minVersionForCollab,
        oldestSupportedClient,
        `${name} minimum collaboration version changed`,
      );
      assert.equal(measured.metadata.createContainerRuntimeVersion, reference.version,
        `${name} runtime package metadata changed`);
      assert.deepEqual(checkpoint.targets.document.attributes, channelAttributes.tree,
        `${name} document schema attributes changed`);
      assert.deepEqual(checkpoint.targets.map.attributes, channelAttributes.map,
        `${name} SharedMap schema attributes changed`);
      assert.deepEqual(checkpoint.targets.tree.attributes, channelAttributes.tree,
        `${name} SharedTree schema attributes changed`);
      assert.deepEqual(measured.factories.document, {
        packagePath: [handleServiceStore.type],
        summaryFormatVersion: 2,
        isRootDataStore: true,
      }, `${name} primary root factory metadata changed`);
      const expectedTargetFactory = checkpoint.id === "same-datastore"
        ? {
          packagePath: [handleServiceStore.type],
          summaryFormatVersion: 2,
          isRootDataStore: true,
        }
        : {
          packagePath: [handleGraphStore.type],
          summaryFormatVersion: 2,
          isRootDataStore: false,
        };
      assert.deepEqual(measured.factories.map, expectedTargetFactory,
        `${name} selected SharedMap factory or root metadata changed`);
      assert.deepEqual(measured.factories.tree, expectedTargetFactory,
        `${name} selected SharedTree factory or root metadata changed`);
      if (checkpoint.id !== "same-datastore") {
        assert.deepEqual(measured.factories.secondary, expectedTargetFactory,
          `${name} declared secondary factory or layout changed`);
      }
      const documentGraph = measured.targets.document.graph;
      assert.equal(documentGraph.links.map, checkpoint.targets.map.path,
        `${name} document map handle path changed`);
      assert.equal(documentGraph.links.tree, checkpoint.targets.tree.path,
        `${name} document tree handle path changed`);
      assert.deepEqual(documentGraph.sequence, [
        checkpoint.targets.map.path,
        checkpoint.targets.tree.path,
      ], `${name} document handle order changed`);
      assert.equal(measured.targets.map.graph.self, checkpoint.targets.map.path,
        `${name} SharedMap self handle changed`);
      assert.equal(measured.targets.map.graph.tree, checkpoint.targets.tree.path,
        `${name} SharedMap tree handle changed`);
      assert.equal(measured.targets.tree.graph.optional, checkpoint.targets.map.path,
        `${name} SharedTree map handle changed`);
      const label = `handleReloadMatrix-${row.writer}-${section.runId.slice(0, 8)}`;
      const targetKind = checkpoint.id === "same-datastore" ? "same" : "cross";
      assert.equal(measured.targets.map.graph.value, `${label}-${targetKind}-map`,
        `${name} selected SharedMap value changed`);
      if (checkpoint.id !== "handle-undo-redo") {
        assert.equal(
          measured.targets.tree.graph.label,
          `${label}-${targetKind}-tree`,
          `${name} selected SharedTree value changed`,
        );
      }
      for (const target of Object.values(checkpoint.targets)) {
        gcNode(measured.gc, target.path,
          `${name} ${row.writer}:${checkpoint.id}`);
      }
      validatePublication(name, {
        writer: row.writer,
        raw: {
          publication: checkpoint.publication,
          sequenced: checkpoint.sequenced,
        },
        snapshot: checkpoint.snapshot,
      }, raw);
      checkpointById.set(`${row.writer}:${checkpoint.id}`, {
        checkpoint: fullCheckpoint,
      });
    }
  }
  const seenFresh = new Set();
  const expectedStates = new Map([...checkpointById].map(([id, { checkpoint }]) =>
    [id, matrixStoredBefore(checkpoint)]));
  const stateWatermarks = new Map([...checkpointById].map(
    ([id, { checkpoint }]) => [
      id,
      checkpoint.snapshot.evidence.referenceSequenceNumber,
    ],
  ));
  for (const cell of section.cells) {
    const [writer, checkpoint, reader] = cell.id.split(":");
    assert.equal(cell.writer, writer, `${name} cell writer differs from its ID`);
    assert.equal(cell.checkpoint, checkpoint,
      `${name} cell checkpoint differs from its ID`);
    assert.equal(cell.reader, reader, `${name} cell reader differs from its ID`);
    assert(writers.includes(reader), `${name} cell reader is unknown`);
    assert(typeof cell.freshIdentity?.instanceId === "string"
      && cell.freshIdentity.instanceId.length > 0,
    `${name} cell lacks a genuine fresh reader identity`);
    assert(Array.isArray(cell.freshIdentity.clientIds)
      && cell.freshIdentity.clientIds.length > 0,
    `${name} cell lacks fresh reader client identities`);
    for (const identity of cell.freshIdentity.clientIds) {
      assert(!seenFresh.has(identity), `${name} reused or forged a fresh reader identity`);
      seenFresh.add(identity);
    }
    const stored = checkpointById.get(`${writer}:${checkpoint}`);
    assert(stored, `${name} cell names an unproduced checkpoint`);
    assert.equal(cell.loadedVersion, stored.checkpoint.snapshot.version,
      `${name} cell loaded another published version`);
    const stateId = `${writer}:${checkpoint}`;
    if (checkpoint === "handle-undo-redo" && reader === writers[0]) {
      const priorId = `${writer}:cross-datastore`;
      assert(
        stored.checkpoint.snapshot.evidence.referenceSequenceNumber
          >= stateWatermarks.get(priorId),
        `${name} republished checkpoint precedes the decoded continuation tail`,
      );
      assert.deepEqual(
        expectedStates.get(stateId),
        expectedStates.get(priorId),
        `${name} republished checkpoint lost its decoded continuation tail`,
      );
    }
    const expectedBefore = expectedStates.get(stateId);
    assert.deepEqual(cell.before, expectedBefore,
      `${name} cell loaded state differs from stored bytes and sequenced tail`);
    assert.deepEqual(cell.expectedBefore, expectedBefore,
      `${name} copied expected state differs from stored bytes and sequenced tail`);
    assert.deepEqual(cell.resolved, {
      document: stored.checkpoint.targets.document.path,
      map: stored.checkpoint.targets.map.path,
      tree: stored.checkpoint.targets.tree.path,
      mapTree: stored.checkpoint.targets.tree.path,
      treeMap: stored.checkpoint.targets.map.path,
    }, `${name} cell did not resolve actual loaded handles`);
    validateMatrixLoader(
      name,
      reader,
      reader === "upstream"
        ? {
          loadedVersion: cell.loadedVersion,
          loader: cell.loader,
          storage: cell.storage,
        }
        : {
          loadedVersion: cell.loadedVersion,
          loader: cell.loader,
          transport: cell.transport,
        },
      stored.checkpoint,
    );
    const effects = validateMatrixContinuation(name, cell, stored.checkpoint);
    assert.equal(
      cell.continuation.peer.state.continuation,
      cell.continuation.value,
      `${name} cell peer did not observe the continuing target write`,
    );
    assert.equal(
      cell.continuation.peer.state.treeLabel,
      cell.continuation.treeLabel,
      `${name} cell peer did not observe the continuing tree write`,
    );
    assert.equal(cell.continuation.peer.state.map, stored.checkpoint.targets.map.path,
      `${name} continuation peer resolved another SharedMap`);
    assert.equal(cell.continuation.peer.state.tree, stored.checkpoint.targets.tree.path,
      `${name} continuation peer resolved another SharedTree`);
    expectedStates.set(stateId, {
      ...expectedBefore,
      treeLabel: effects.tree.label,
      continuations: [
        ...expectedBefore.continuations,
        [effects.map.key, effects.map.value],
      ].sort(([left], [right]) => left.localeCompare(right)),
    });
    stateWatermarks.set(stateId, Math.max(
      effects.map.sequenceNumber,
      effects.tree.sequenceNumber,
    ));
  }
  return section;
}

async function validateRow(name, row, artifacts) {
  if (name === "handleTransactionBranch") {
    return validateTransactionBranchRow(name, row, artifacts);
  }
  if (name === "handleRetention") {
    return validateRetentionRow(name, row, artifacts);
  }
  if (name === "handleReconnect") {
    return validateReconnectRow(name, row, artifacts);
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

function scheduleRequiredMessages(operations) {
  return [
    operations.attachment.message,
    operations.parentReference.message,
    operations.targetState.message,
  ];
}

function scheduleOutboundMessages(entries) {
  return submissionMessages(entries.filter(({ direction }) =>
    direction === undefined || direction === "outbound"));
}

function scheduleInboundMessages(entries) {
  return entries.filter(({ direction }) => direction === "inbound")
    .flatMap(({ sequencedMessages = [] }) => sequencedMessages)
    .filter(({ type }) => type === "op");
}

function coversScheduleMessages(actual, expected, key = operationIdentityKey) {
  const keys = new Set(actual.map(key));
  return expected.every((message) => keys.has(key(message)));
}

function typedOperationIdentityKey(message) {
  return `${message.type}:${operationIdentityKey(message)}`;
}

function sequencedOperationIdentityKey(message) {
  return [
    message.sequenceNumber,
    typedOperationIdentityKey(message),
  ].join(":");
}

function scheduleLifecycleLogicalOperations(messages, record) {
  const parent = [];
  for (const message of messages) {
    const references = scheduleHandleReferences([message])
      .filter(({ key, path }) =>
        key === record.id && path === record.target.path);
    for (const submission of decodeTreeSubmissions([message])) {
      for (const commit of submission.commits) {
        const reference = references.find((candidate) =>
          candidate.innerIndex === commit.innerIndex
            && candidate.revision === commit.revision
            && candidate.originatorId === commit.originatorId);
        if (!reference) continue;
        parent.push({
          key: reference.key,
          path: reference.path,
          revision: commit.revision,
          originatorId: commit.originatorId,
          changeset: jsonClone(commit.changeset),
          allocations: jsonClone(submission.allocations),
        });
      }
    }
  }
  return {
    parent,
    target: scheduleMapSets(messages, record.target.path)
      .filter(({ key, value }) =>
        key === "value" && value === record.local.value)
      .map(({ target, key, value }) => ({ target, key, value })),
  };
}

function validateScheduleRetryLineage(
  originalMessages,
  acceptedMessages,
  record,
  label,
) {
  const original = scheduleLifecycleLogicalOperations(originalMessages, record);
  const accepted = scheduleLifecycleLogicalOperations(acceptedMessages, record);
  assert.equal(original.parent.length, 1,
    `${label} original retry lineage lacks one parent commit`);
  assert.equal(accepted.parent.length, 1,
    `${label} accepted retry lineage lacks one parent commit`);
  assert.equal(original.target.length, 1,
    `${label} original retry lineage lacks one target command`);
  assert.equal(accepted.target.length, 1,
    `${label} accepted retry lineage lacks one target command`);
  assert.deepEqual(
    original.parent.map(({
      key, path, revision, originatorId, changeset,
    }) => ({ key, path, revision, originatorId, changeset })),
    accepted.parent.map(({
      key, path, revision, originatorId, changeset,
    }) => ({ key, path, revision, originatorId, changeset })),
    `${label} original and accepted logical parent commits differ`,
  );
  assert.deepEqual(original.target, accepted.target,
    `${label} original and accepted logical target commands differ`);
  const originalCommit = original.parent[0];
  assert(originalCommit.allocations.length > 0
    && originalCommit.allocations.some(({ sessionId }) =>
      sessionId === originalCommit.originatorId),
  `${label} original and accepted allocation lineage differs`);
  assert(originalCommit.allocations.every(({ sessionId, first, last }) =>
    record.dependencies.allocations.some((allocation) =>
      allocation.sessionId === sessionId
        && allocation.first === first
        && allocation.last === last)),
  `${label} original allocation ranges lack accepted sequenced evidence`);
}

function expectedScheduleActors(disconnectMode) {
  return disconnectMode ? ["writer"] : ["writer", "target"];
}

function actorDeliveryEntries(actors, key) {
  return Object.entries(actors).flatMap(([actor, evidence]) =>
    evidence[key].map((item) => ({ actor, ...item })));
}

function validateReadyNativeObservation(observation, clientIds, label) {
  assert(observation
    && observation.phase === "ready"
    && observation.synced === true
    && observation.error === null
    && observation.inFlightCount === 0
    && observation.pendingTreeCount === 0
    && clientIds.includes(observation.clientId),
  `${label} is not ready, synced, error-free, and bound to its client`);
}

function validateScheduleDelivery(name, record, plan, required) {
  const delivery = record.delivery;
  const disconnectMode = plan.mode === "disconnect-before-acceptance"
    || plan.mode === "disconnect-after-acceptance";
  const expectedActors = expectedScheduleActors(disconnectMode);
  assert.deepEqual(Object.keys(delivery.actors), expectedActors,
    `${name} ${record.id} delivery actor set changed`);
  for (const key of [
    "held", "controls", "delivered", "handshakes", "connections",
  ]) {
    assert.deepEqual(delivery[key], actorDeliveryEntries(delivery.actors, key),
      `${name} ${record.id} aggregate ${key} differ from actor evidence`);
  }
  assert.deepEqual(
    delivery.submitted,
    Object.values(delivery.actors)
      .flatMap(({ submitted: occurrences }) => occurrences),
    `${name} ${record.id} aggregate submissions differ from actor evidence`,
  );
  assert.equal(
    delivery.errorsBefore,
    Object.values(delivery.actors)
      .reduce((sum, evidence) => sum + evidence.errorsBefore, 0),
    `${name} ${record.id} aggregate initial errors differ from actor evidence`,
  );
  assert.equal(
    delivery.errorsAfter,
    Object.values(delivery.actors)
      .reduce((sum, evidence) => sum + evidence.errorsAfter, 0),
    `${name} ${record.id} aggregate final errors differ from actor evidence`,
  );
  const operations = {
    writer: disconnectMode ? required : required.filter((message) =>
      operationIdentityKey(message)
        !== operationIdentityKey(record.operations.targetState.message)),
    ...(disconnectMode ? {} : {
      target: [record.operations.targetState.message],
    }),
  };
  assert(coversScheduleMessages(
    scheduleOutboundMessages(delivery.submitted),
    required,
  ), `${name} ${record.id} submissions lack all three accepted operations`);
  const issueOrder = plan.operationOrder === "target-first"
    ? ["target-state", "parent-reference"]
    : ["parent-reference", "target-state"];
  assert.deepEqual(delivery.issueOrder, issueOrder,
    `${name} ${record.id} actual operation issue order changed`);
  const issuedActors = issueOrder.map((operation) =>
    operation === "target-state" && !disconnectMode ? "target" : "writer");
  assert.deepEqual(
    delivery.releaseActors,
    [...new Set(plan.releaseOrder === "reverse"
      ? issuedActors.toReversed()
      : issuedActors)],
    `${name} ${record.id} actual actor release order changed`,
  );
  const scheduled = {
    writer: disconnectMode
      ? issueOrder.map((operation) =>
        operation === "parent-reference"
          ? record.operations.parentReference.message
          : record.operations.targetState.message)
      : [record.operations.parentReference.message],
    ...(disconnectMode ? {} : {
      target: [record.operations.targetState.message],
    }),
  };
  for (const [actor, evidence] of Object.entries(delivery.actors)) {
    assert.equal(evidence.errorsAfter, evidence.errorsBefore,
      `${name} ${record.id} ${actor} transport reported errors`);
    assert(typeof evidence.instanceId === "string"
      && evidence.instanceId.length > 0
      && evidence.clientIds.length > 0,
    `${name} ${record.id} ${actor} process identity is missing`);
    assert(expectedActors.includes(actor),
      `${name} ${record.id} has an unexpected ${actor} delivery actor`);
    const processed = actor === "writer"
      ? evidence.observation?.sequenceNumber
      : evidence.observation?.sequenceNumber;
    assert(Number.isSafeInteger(processed)
      && processed >= Math.max(...operations[actor]
        .map(({ sequenceNumber }) => sequenceNumber)),
    `${name} ${record.id} ${actor} processed watermark is incomplete`);
    if (actor === "target" || plan.writer !== "upstream") {
      validateReadyNativeObservation(
        evidence.observation.observation,
        evidence.clientIds,
        `${name} ${record.id} ${actor} author`,
      );
    }
    assert(coversScheduleMessages(
      scheduleOutboundMessages(evidence.submitted),
      operations[actor],
    ), `${name} ${record.id} ${actor} lacks its authenticated submissions`);
  }
  if (plan.mode === "unheld") {
    for (const [actor, evidence] of Object.entries(delivery.actors)) {
      assert.equal(evidence.controls.length, 0,
        `${name} ${record.id} ${actor} unheld transport has controls`);
      assert(coversScheduleMessages(
        scheduleOutboundMessages(evidence.delivered),
        operations[actor],
      ), `${name} ${record.id} ${actor} outbound delivery lacks its operation`);
      assert(coversScheduleMessages(
        scheduleInboundMessages(evidence.delivered),
        operations[actor],
      ), `${name} ${record.id} ${actor} inbound delivery lacks its operation`);
    }
    return;
  }
  const direction = plan.mode === "outbound-held"
      || plan.mode === "disconnect-before-acceptance"
    ? "outbound"
    : "inbound";
  const acceptedCore = [
    record.operations.parentReference.message,
    record.operations.targetState.message,
  ].sort((left, right) => left.sequenceNumber - right.sequenceNumber);
  for (const [actor, evidence] of Object.entries(delivery.actors)) {
    const controls = evidence.controls;
    assert(controls[0]?.action === "hold"
      && controls[0].direction === direction
      && controls[0].kind === "op",
    `${name} ${record.id} ${actor} lacks its actual hold`);
    const heldMessages = direction === "outbound"
      ? scheduleOutboundMessages(evidence.held)
      : scheduleInboundMessages(evidence.held);
    const expectedHeld = direction === "outbound"
      ? scheduled[actor]
      : acceptedCore;
    if (direction === "outbound") {
      assert(coversScheduleMessages(
        scheduleOutboundMessages(evidence.submitted),
        heldMessages,
        typedOperationIdentityKey,
      ), `${name} ${record.id} ${actor} outbound hold lacks its submission `
        + "identity");
      if (plan.mode === "outbound-held") {
        assert.deepEqual(
          heldMessages.map(typedOperationIdentityKey),
          expectedHeld.map(typedOperationIdentityKey),
          `${name} ${record.id} ${actor} outbound hold identity changed`,
        );
      }
    } else {
      assert.deepEqual(
        heldMessages.map(sequencedOperationIdentityKey).sort(),
        expectedHeld.map(sequencedOperationIdentityKey).sort(),
        `${name} ${record.id} ${actor} inbound hold identity changed`,
      );
    }
    const hasWriterOperation = actor !== "writer"
      || scheduleHandleReferences(heldMessages).some(({ key, path }) =>
        key === record.id && path === record.target.path);
    const hasTargetOperation = actor !== "target" && !disconnectMode
      || scheduleMapSets(heldMessages, record.target.path)
        .some(({ key, value }) =>
          key === "value" && value === record.local.value);
    assert(hasWriterOperation && hasTargetOperation,
      `${name} ${record.id} ${actor} hold lacks decoded lifecycle operations`);
    const heldIds = evidence.held.filter(({ direction: candidate, kind }) =>
      candidate === direction && kind === "op").map(({ id }) => id);
    assert(heldIds.length > 0,
      `${name} ${record.id} ${actor} hold lacks message identities`);
    if (plan.mode === "outbound-held" || plan.mode === "inbound-held") {
      const release = controls.find(({ action }) => action === "release");
      assert(release && release.direction === direction,
        `${name} ${record.id} ${actor} release direction changed`);
      assert.deepEqual(release.messageIds, heldIds,
        `${name} ${record.id} ${actor} release differs from held identities`);
      assert.deepEqual(
        evidence.delivered.filter(({ id }) => heldIds.includes(id))
          .map(({ id }) => id),
        heldIds,
        `${name} ${record.id} ${actor} held packet delivery order changed`,
      );
      const deliveredMessages = direction === "outbound"
        ? scheduleOutboundMessages(evidence.delivered
          .filter(({ id }) => heldIds.includes(id)))
        : scheduleInboundMessages(evidence.delivered
          .filter(({ id }) => heldIds.includes(id)));
      assert.deepEqual(
        direction === "outbound"
          ? deliveredMessages.map(typedOperationIdentityKey)
          : deliveredMessages.map(sequencedOperationIdentityKey),
        direction === "outbound"
          ? heldMessages.map(typedOperationIdentityKey)
          : heldMessages.map(sequencedOperationIdentityKey),
        `${name} ${record.id} ${actor} delivered packet identity changed`,
      );
      continue;
    }
    const disconnect = controls.find(({ action }) => action === "disconnect");
    const reconnect = controls.find(({ action }) => action === "reconnect");
    assert(disconnect && reconnect
      && controls.indexOf(disconnect) < controls.indexOf(reconnect),
    `${name} ${record.id} ${actor} disconnect window is out of order`);
    assert.deepEqual(disconnect.dropped[direction], heldIds,
      `${name} ${record.id} ${actor} disconnect lacks dropped identities`);
    assert.deepEqual(disconnect.dropped[direction === "inbound"
      ? "outbound"
      : "inbound"], [],
    `${name} ${record.id} ${actor} disconnect dropped another direction`);
    assert(!evidence.delivered.some(({ id }) => heldIds.includes(id)),
      `${name} ${record.id} ${actor} dropped operation claims delivery`);
    const heldConnections = new Set(evidence.held
      .filter(({ id }) => heldIds.includes(id))
      .map(({ connectionId }) => connectionId));
    const preWindow = evidence.preWindow;
    assert(preWindow
      && Array.isArray(preWindow.connections)
      && Array.isArray(preWindow.handshakes),
    `${name} ${record.id} ${actor} lacks pre-disconnect transport receipts`);
    assert.deepEqual(
      preWindow.connections.map(({ connectionId }) => connectionId).sort(),
      [...heldConnections].sort(),
      `${name} ${record.id} ${actor} pre-disconnect connections changed`,
    );
    const originalClients = new Map(preWindow.handshakes.map((handshake) => [
      handshake.connectionId,
      handshake.clientId,
    ]));
    assert.deepEqual(
      [...originalClients.keys()].sort(),
      [...heldConnections].sort(),
      `${name} ${record.id} ${actor} pre-disconnect handshakes changed`,
    );
    const heldOccurrences = evidence.held.filter(({ id }) =>
      heldIds.includes(id));
    if (plan.mode === "disconnect-before-acceptance") {
      for (const occurrence of heldOccurrences) {
        const clientId = originalClients.get(occurrence.connectionId);
        assert(typeof clientId === "string"
          && evidence.clientIds.includes(clientId)
          && submissionMessages([occurrence]).every((message) =>
            message.clientId === clientId),
        `${name} ${record.id} ${actor} original submission client changed`);
      }
      const heldMessagesByConnection = Map.groupBy(
        heldOccurrences.flatMap((occurrence) =>
          submissionMessages([occurrence]).map((message) => ({
            connectionId: occurrence.connectionId,
            message,
          }))),
        ({ connectionId }) => connectionId,
      );
      for (const [connectionId, entries] of heldMessagesByConnection) {
        const clientId = originalClients.get(connectionId);
        const heldMessagesForConnection = entries.map(({ message }) => message);
        const prior = evidence.submitted
          .filter(({ id, connectionId: candidate }) =>
            candidate === connectionId && !heldIds.includes(id))
          .flatMap((occurrence) => submissionMessages([occurrence]))
          .filter((message) => message.clientId === clientId);
        const priorClientSequence = Math.max(
          0,
          ...prior.map(({ clientSequenceNumber }) => clientSequenceNumber),
        );
        assert.deepEqual(
          heldMessagesForConnection
            .map(({ clientSequenceNumber }) =>
              clientSequenceNumber).sort((a, b) => a - b),
          Array.from(
            { length: heldMessagesForConnection.length },
            (_, index) => priorClientSequence + index + 1,
          ),
          `${name} ${record.id} ${actor} original client sequence changed`,
        );
        const priorReferenceSequence = Math.max(
          0,
          ...prior.map(({ referenceSequenceNumber }) => referenceSequenceNumber),
        );
        assert(heldMessagesForConnection.every(({ referenceSequenceNumber }) =>
          Number.isSafeInteger(referenceSequenceNumber)
            && referenceSequenceNumber >= priorReferenceSequence
            && referenceSequenceNumber <= Math.min(...scheduled[actor]
              .map((message) => message.referenceSequenceNumber))),
        `${name} ${record.id} ${actor} original reference sequence changed`);
      }
    }
    const reconnectConnections = new Set(evidence.handshakes
      .map(({ connectionId }) => connectionId));
    const reconnectMessages = [
      ...evidence.delivered
        .filter(({ direction: candidate, connectionId }) =>
          candidate === "inbound"
            && reconnectConnections.has(connectionId))
        .flatMap(({ sequencedMessages = [] }) => sequencedMessages),
      ...evidence.handshakes
        .filter(({ connectionId }) => reconnectConnections.has(connectionId))
        .flatMap(({ initialMessages = [] }) => initialMessages),
    ];
    assert(reconnectConnections.size > 0
      && [...reconnectConnections].every((connectionId) =>
        !heldConnections.has(connectionId))
      && evidence.connections.some(({ connectionId }) =>
        reconnectConnections.has(connectionId)),
    `${name} ${record.id} ${actor} reconnect did not change connections`);
    if (plan.mode === "disconnect-before-acceptance") {
      const retryClients = new Map(evidence.handshakes.map((handshake) => [
        handshake.connectionId,
        handshake.clientId,
      ]));
      const retryOccurrences = evidence.delivered.filter(({
        direction: candidate, kind, connectionId, submissions,
      }) => candidate === "outbound"
        && kind === "op"
        && Array.isArray(submissions)
        && reconnectConnections.has(connectionId));
      assert(retryOccurrences.every((occurrence) => {
        const clientId = retryClients.get(occurrence.connectionId);
        return typeof clientId === "string"
          && evidence.clientIds.includes(clientId)
          && submissionMessages([occurrence]).every((message) =>
            message.clientId === clientId);
      }), `${name} ${record.id} ${actor} retry submission client changed`);
      assert(coversScheduleMessages(
        scheduleOutboundMessages(retryOccurrences),
        scheduled[actor],
      ), `${name} ${record.id} ${actor} retry lacks its accepted operation`);
      assert(evidence.delivered.some(({ direction: candidate, connectionId }) =>
        candidate === "outbound" && reconnectConnections.has(connectionId)),
      `${name} ${record.id} ${actor} retry reused the disconnected transport`);
      assert(coversScheduleMessages(
        reconnectMessages,
        scheduled[actor],
        sequencedOperationIdentityKey,
      ), `${name} ${record.id} ${actor} retry acceptance identity changed`);
      validateScheduleRetryLineage(
        heldMessages,
        scheduled[actor],
        record,
        `${name} ${record.id} ${actor}`,
      );
    } else {
      const through = Math.max(
        ...scheduled[actor].map(({ sequenceNumber }) => sequenceNumber),
      );
      assert(evidence.handshakes.some(({ checkpointSequenceNumber,
        summarySequenceNumber, initialMessageSequenceNumbers = [] }) =>
        Math.max(
          checkpointSequenceNumber ?? -1,
          summarySequenceNumber ?? -1,
          ...initialMessageSequenceNumbers,
        ) >= through),
      `${name} ${record.id} ${actor} reconnect does not cover acceptance`);
      assert(coversScheduleMessages(
        reconnectMessages,
        scheduled[actor],
        sequencedOperationIdentityKey,
      ), `${name} ${record.id} ${actor} reconnect replay identity changed`);
    }
  }
}

async function validateLifecycleSchedules(section, artifacts) {
  const name = "handleSchedules";
  assert(section && typeof section === "object", `${name} section is missing`);
  assert.equal(section.name, name, `${name} section name changed`);
  assert.equal(section.formatVersion, 1, `${name} format changed`);
  assert.equal(section.runId, artifacts.runId, `${name} run identity changed`);
  validateContract(section.contract, `${name} section`);
  assert.equal(section.skipped, false, `${name} section is skipped`);
  assert.equal(section.seed, lifecycleScheduleSeed,
    `${name} requires fixed seed 42`);
  assert.equal(section.requested, lifecycleScheduleCount,
    `${name} requires exactly 300 schedules`);
  const plans = lifecycleSchedulePlans();
  assert.deepEqual(section.expectedIds, plans.map(({ id }) => id),
    `${name} fixed schedule IDs changed`);
  assert.equal(section.records.length, lifecycleScheduleCount,
    `${name} requires exactly 300 actual schedules`);
  assert.deepEqual(section.records.map(({ id }) => id), section.expectedIds,
    `${name} missing, duplicate, or reordered schedule IDs`);
  assert.equal(new Set(section.records.map(({ id }) => id)).size,
    lifecycleScheduleCount, `${name} duplicate schedule IDs`);
  assert.equal(new Set(section.records.map(({ target }) =>
    `${target.documentId}:${target.path}`)).size,
    lifecycleScheduleCount, `${name} reused an actual target identity`);
  assert.deepEqual(
    [...new Set(section.observers.map(({ writer }) => writer))].sort(),
    [...writers].sort(),
    `${name} observer writer coverage changed`,
  );
  assert.equal(section.observers.length,
    writers.length * lifecycleScheduleCount
      / writers.length / lifecycleScheduleBatchSize,
  `${name} observer batch coverage changed`);
  const observerByInstance = new Map(
    section.observers.map((observer) => [observer.instanceId, observer]),
  );
  assert.equal(observerByInstance.size, section.observers.length,
    `${name} reused an observer process`);
  for (const [index, record] of section.records.entries()) {
    const plan = plans[index];
    assert.deepEqual({
      id: record.id,
      index: record.index,
      writer: record.writer,
      mode: record.delivery.mode,
      releaseOrder: record.delivery.releaseOrder,
      operationOrder: record.delivery.operationOrder,
    }, plan, `${name} ${record.id} delivery plan changed`);
    assert.equal(record.seed, lifecycleScheduleSeed,
      `${name} ${record.id} seed changed`);
    assert.deepEqual(record.target.attributes, channelAttributes.map,
      `${name} ${record.id} target attributes changed`);
    assert(typeof record.target.documentId === "string"
      && record.target.documentId.length > 0,
    `${name} ${record.id} target document identity is missing`);
    assert.equal(record.local.value, `schedule-value-${record.id}`,
      `${name} ${record.id} local map read differs from its authored value`);
    assert.equal(record.local.handlePath, record.target.path,
      `${name} ${record.id} local handle names another target`);
    assert.equal(record.peer.target, record.target.path,
      `${name} ${record.id} native peer resolved another target`);
    assert.equal(record.peer.upstream.target, record.target.path,
      `${name} ${record.id} upstream peer resolved another target`);
    assert.equal(record.peer.value, record.local.value,
      `${name} ${record.id} peer value diverged`);
    assert.equal(record.peer.upstream.value, record.local.value,
      `${name} ${record.id} upstream peer value diverged`);
    assert.equal(record.actualHandleWork, true,
      `${name} ${record.id} lacks actual handle work`);
    assert.equal(record.skipped, false,
      `${name} ${record.id} is skipped`);
    assert.equal(record.divergence, false,
      `${name} ${record.id} reports divergence`);
    assert.equal(record.delivery.errorsAfter, record.delivery.errorsBefore,
      `${name} ${record.id} delivery transport reported errors`);
    const operations = scheduleOperationEvidence(
      record.operations.sequenced,
      plan,
      record.target,
      record.local.value,
    );
    assert.deepEqual(record.operations, operations,
      `${name} ${record.id} decoded lifecycle operations changed`);
    assert.deepEqual(record.dependencies, dependencyEvidence(
      operations.sequenced,
      { target: record.target },
    ), `${name} ${record.id} decoded allocation and commit evidence changed`);
    const required = scheduleRequiredMessages(operations);
    assert(record.accepted?.type === "op"
      && Number.isSafeInteger(record.accepted.sequenceNumber)
      && record.accepted.sequenceNumber > 0
      && Number.isSafeInteger(record.accepted.clientSequenceNumber)
      && Number.isSafeInteger(record.accepted.referenceSequenceNumber)
      && typeof record.accepted.clientId === "string"
      && record.accepted.clientId.length > 0,
    `${name} ${record.id} lacks an actual typed accepted operation`);
    assert.deepEqual(record.accepted, operations.parentReference.message,
      `${name} ${record.id} accepted operation is not its decoded parent reference`);
    assert(submissionMessages(record.delivery.submitted).some((message) =>
      operationIdentityKey(message) === operationIdentityKey(record.accepted)),
    `${name} ${record.id} accepted operation differs from actual delivery identity`);
    validateScheduleDelivery(name, record, plan, required);
    const throughSequenceNumber = Math.max(
      ...operations.sequenced.map(({ sequenceNumber }) => sequenceNumber),
    );
    assert(record.local.writerObservation
      && record.local.writerObservation.instanceId === record.local.writerInstanceId
      && record.local.writerClientIds.includes(record.local.writerObservation.clientId)
      && record.local.writerObservation.sequenceNumber >= throughSequenceNumber
      && record.local.writerObservation.pendingTreeCount === 0
      && record.local.writerObservation.inflightSubmissionCount === 0
      && (plan.writer === "upstream"
        || !record.local.writerObservation.readError),
    `${name} ${record.id} writer observation does not cover all accepted edits`);
    assert.equal(
      record.delivery.actors.writer.instanceId,
      record.local.writerInstanceId,
      `${name} ${record.id} writer delivery belongs to another process`,
    );
    assert.deepEqual(
      [...record.delivery.actors.writer.clientIds].sort(),
      [...record.local.writerClientIds].sort(),
      `${name} ${record.id} writer delivery client identities changed`,
    );
    if (plan.writer !== "upstream") {
      validateReadyNativeObservation(
        record.local.writerObservation.observation,
        record.local.writerClientIds,
        `${name} ${record.id} native writer observation`,
      );
    }
    const observer = observerByInstance.get(record.observer.instanceId);
    assert(observer
      && observer.writer === record.writer
      && observer.implementation === record.observer.implementation,
    `${name} ${record.id} observer identity changed`);
    assert.equal(record.observer.instanceId, observer.instanceId,
      `${name} ${record.id} observer process identity changed`);
    assert.equal(observer.transport.instanceId, observer.instanceId,
      `${name} ${record.id} native transport belongs to another process`);
    assert.equal(record.observer.acceptedSequenceNumber, throughSequenceNumber,
      `${name} ${record.id} observer acceptance watermark changed`);
    assert(record.observer.processedSequenceNumber >= throughSequenceNumber
      && record.observer.observation.phase === "ready"
      && record.observer.observation.synced === true
      && record.observer.observation.error === null
      && record.observer.observation.inFlightCount === 0
      && record.observer.observation.pendingTreeCount === 0,
    `${name} ${record.id} per-schedule observer did not process all edits`);
    assert.equal(
      record.observer.observation.clientId,
      observer.observation.clientId,
      `${name} ${record.id} per-schedule observer processed another client`,
    );
    assert(observer.clientIds.includes(record.observer.observation.clientId),
      `${name} ${record.id} per-schedule observer client is not connected`);
    assert.equal(record.peer.native.instanceId, observer.instanceId,
      `${name} ${record.id} native map read belongs to another process`);
    assert.deepEqual(
      [...record.peer.native.clientIds].sort(),
      [...observer.clientIds].sort(),
    `${name} ${record.id} native map read client identities changed`);
    assert.equal(record.peer.native.target, record.target.path,
      `${name} ${record.id} native map read names another target`);
    assert.equal(record.peer.native.value, record.local.value,
      `${name} ${record.id} native map read has another value`);
    const upstreamPeer = record.peer.upstream;
    assert(upstreamPeer
      && upstreamPeer.instanceId === upstreamPeer.observation?.clientId
      && upstreamPeer.processedSequenceNumber
        === upstreamPeer.observation?.lastSequenceNumber
      && upstreamPeer.processedSequenceNumber >= throughSequenceNumber
      && Array.isArray(upstreamPeer.clientIds)
      && upstreamPeer.clientIds.includes(upstreamPeer.instanceId)
      && upstreamPeer.transport?.connections.some(({ clientId }) =>
        clientId === upstreamPeer.instanceId),
    `${name} ${record.id} upstream map read lacks its processed connection identity`);
    const actorClientIds = new Set(
      Object.values(record.delivery.actors)
        .flatMap(({ clientIds }) => clientIds),
    );
    assert(!upstreamPeer.clientIds.some((clientId) =>
      actorClientIds.has(clientId)),
    `${name} ${record.id} upstream map read reused a writer or target client`);
    assert(observer.observation.phase === "ready"
      && observer.observation.synced === true
      && observer.observation.error === null
      && observer.observation.inFlightCount === 0
      && observer.observation.pendingTreeCount === 0,
    `${name} ${record.id} native observer is not ready, synced, and error-free: `
      + JSON.stringify(observer.observation));
    assert.deepEqual(observer.transport.errors, [],
      `${name} ${record.id} native observer transport reported errors`);
    assert(observer.processedSequenceNumber >= throughSequenceNumber,
      `${name} ${record.id} observer processed watermark precedes required edits`);
    assert(observer.clientIds.includes(observer.observation.clientId),
      `${name} ${record.id} observer processed another client identity`);
    const connectionIds = new Set(
      observer.transport.connections.map(({ connectionId }) => connectionId),
    );
    const receipts = matrixSequencedMessageReceipts(
      observer.transport,
      connectionIds,
      true,
    );
    for (const message of operations.sequenced) {
      const receiptKey = [
        message.sequenceNumber,
        message.type,
        operationIdentityKey(message),
      ].join(":");
      assert(receipts.has(receiptKey),
        `${name} ${record.id} required edit lacks native inbound identity`);
      assert(observer.transport.handshakes.some(({ connectionId, clientId }) =>
        clientId === record.observer.observation.clientId
          && receipts.get(receiptKey).has(connectionId)),
      `${name} ${record.id} observer handshake differs from delivered edit`);
    }
  }
  assert(new Set(section.records.map(({ delivery }) => delivery.mode)).size >= 5,
    `${name} lacks varied real delivery and reconnect windows`);
  assert.deepEqual(
    [...new Set(section.records.map(({ delivery }) => delivery.releaseOrder))].sort(),
    ["fifo", "reverse"],
    `${name} lacks varied delivery release order`,
  );
  assert.deepEqual(
    [...new Set(section.records.map(({ delivery }) => delivery.operationOrder))].sort(),
    ["parent-first", "target-first"],
    `${name} lacks varied handle operation order`,
  );
  assert.equal(section.artifacts.length, 1,
    `${name} lacks one persisted schedule artifact`);
  const descriptor = section.artifacts[0];
  const registered = artifacts.files[descriptor.path];
  assert(registered, `${name} artifact is not registered`);
  assert.equal(registered.sha256, descriptor.sha256,
    `${name} artifact digest changed`);
  const bytes = await readFile(join(artifacts.root, descriptor.path));
  assert.equal(hash(bytes), descriptor.sha256,
    `${name} persisted artifact bytes changed`);
  const artifact = JSON.parse(bytes.toString("utf8"));
  const persisted = structuredClone(section);
  delete persisted.artifacts;
  assert.deepEqual(artifact, JSON.parse(JSON.stringify(persisted)),
    `${name} report differs from its persisted artifact`);
  return section;
}

export async function validateLifecycleSection(
  name,
  section,
  artifacts,
  { diagnosticWriter } = {},
) {
  if (name === "handleSchedules") {
    return validateLifecycleSchedules(section, artifacts);
  }
  if (name === "handleReloadMatrix") {
    return validateReloadMatrixSection(section, artifacts);
  }
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
  assert.equal(report.bounded, false,
    "Lifecycle bounded diagnostic report is not full acceptance");
  validateContract(report.contract, "Lifecycle report");
  assert.deepEqual(report.prerequisites?.source, {
    commit: sourceReference.commit,
    version: sourceReference.version,
  }, "Lifecycle report reference checkout identity changed");
  assert.deepEqual(report.prerequisites?.capture?.reference, {
    commit: sourceReference.commit,
    version: sourceReference.version,
  }, "Lifecycle report source capture identity changed");
  assert.equal(report.prerequisites?.capture?.minVersionForCollab,
    oldestSupportedClient,
  "Lifecycle report source capture compatibility changed");
  assert(/^[a-f0-9]{64}$/.test(report.prerequisites?.capture?.sha256),
    "Lifecycle report source capture digest is missing");
  assert.deepEqual(
    Object.fromEntries(Object.entries(report.prerequisites?.packages ?? {})
      .map(([name, version]) => [name, version])),
    Object.fromEntries(sourceReference.packages.map((name) =>
      [name, sourceReference.version])),
    "Lifecycle report package pins changed",
  );
  await validateLifecycleSchedules(report.schedules, artifacts);
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
  iterations = lifecycleScheduleCount,
  seed = lifecycleScheduleSeed,
} = {}) {
  assert.equal(iterations, lifecycleScheduleCount,
    "Task 8 lifecycle acceptance requires exactly 300 schedules");
  assert.equal(seed, lifecycleScheduleSeed,
    "Task 8 lifecycle acceptance requires seed 42");
  const runId = randomUUID();
  const matrixSelected = scenario === "handleReloadMatrix";
  const schedulesSelected = scenario === "handleSchedules";
  const selected = scenario === undefined || matrixSelected || schedulesSelected
    ? null
    : scenario.match(/^(handleValues|channelAttachment|datastoreAttachment|handleTransactionBranch|handleRetention|handleReconnect):(upstream|javascript|erlang)$/);
  if (scenario !== undefined) {
    assert(selected || matrixSelected || schedulesSelected,
      "Lifecycle scenario must be <section>:<writer>, handleReloadMatrix, or handleSchedules");
  }
  const selectedSections = schedulesSelected
    ? []
    : matrixSelected
    ? ["handleReloadMatrix"]
    : selected
      ? [selected[1]]
      : bounded
        ? liveSections
        : sections;
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
  const prerequisites = await verifyLifecyclePrerequisites();
  await mkdir(context.output, { recursive: true });
  const report = {
    formatVersion: 1,
    runId,
    contract,
    prerequisites,
    bounded: bounded || scenario !== undefined,
    sections: {},
  };
  for (const name of selectedSections) {
    if (name === "handleReloadMatrix") {
      const section = await runReloadMatrix(config, context);
      await validateLifecycleSection(name, section, context.artifacts);
      report.sections[name] = section;
      continue;
    }
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
  if (schedulesSelected || scenario === undefined && bounded === false) {
    report.schedules = await runLifecycleSchedules(config, context);
    await validateLifecycleSchedules(report.schedules, context.artifacts);
  }
  if (scenario === undefined && bounded === false) {
    await validateLifecycleReport(report, context.artifacts);
  }
  await writeFile(
    join(context.output, "report.json"),
    `${JSON.stringify(report, null, 2)}\n`,
    { mode: 0o600 },
  );
  await writeFile(
    join(context.output, "artifacts.json"),
    `${JSON.stringify(context.artifacts, null, 2)}\n`,
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
      iterations: { type: "string", default: String(lifecycleScheduleCount) },
      output: { type: "string" },
      scenario: { type: "string" },
      seed: { type: "string", default: String(lifecycleScheduleSeed) },
    },
  });
  const iterations = Number(values.iterations);
  const seed = Number(values.seed);
  assert(Number.isSafeInteger(iterations),
    "--iterations must be a safe integer");
  assert(Number.isSafeInteger(seed), "--seed must be a safe integer");
  const run = (config) => runLifecycleInterop({
    config,
    ...(values.output ? { output: values.output } : {}),
    ...(values.scenario ? { scenario: values.scenario } : {}),
    iterations,
    seed,
  });
  const captured = values["local-floodgate"]
    ? await withLocalFloodgate(run)
    : await run(serviceConfig());
  console.log(JSON.stringify({
    runId: captured.report.runId,
    bounded: captured.report.bounded,
    sections: Object.keys(captured.report.sections),
    schedules: captured.report.schedules?.records.length ?? 0,
    seed: captured.report.schedules?.seed,
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
