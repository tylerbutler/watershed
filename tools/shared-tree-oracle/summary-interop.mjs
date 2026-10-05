import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { fileURLToPath, pathToFileURL } from "node:url";
import { isDeepStrictEqual, parseArgs, promisify } from "node:util";
import { SummaryType } from "@fluidframework/driver-definitions/internal";
import { rootDataStoreId } from "@fluidframework/runtime-utils/internal";

import {
  DeliveryGate,
  snapshotSequenceNumber,
  storageResponseIdentity,
} from "./delivery-gate.mjs";
import { Point, schemaEvolutionConfigurations } from "./schema.mjs";
import {
  acceptedTreeOperations,
  canonicalValue,
  captureFailureCheckpoint,
  decodeReconnectPayload,
  decodeTreeSubmissions,
  nativeAdapter,
  preserveFailureCheckpoints,
  publishUpstreamSummary,
  refresherValues,
  rootValue,
  serverHistory,
  settle,
  success,
  until,
  upstreamAdapter,
  waitForAuthorSubmission,
} from "./interop-scenarios.mjs";
import {
  arrayServiceStore,
  identifierServiceStore,
  mapServiceStore,
  openSession,
  preflight,
  schemaEvolutionServiceStore,
  serviceConfig,
  tokenProvider,
  withLocalFloodgate,
} from "./service.mjs";
import { makeEnvironment, publishSummary, readSnapshot } from "./container-corpus.mjs";
import { captureSource, reference } from "./source.mjs";

const directory = dirname(fileURLToPath(import.meta.url));
const repository = resolve(directory, "../..");
const execute = promisify(execFile);
const identity = {
  package: "@fluidframework/tree", version: reference.version, commit: reference.commit,
};
const implementations = ["upstream", "javascript", "erlang"];
const nativeTargets = ["javascript", "erlang"];
const persistenceStates = [
  "initial", "concurrent-detached", "after-peer-leave", "after-nontree-tail",
];

function summaryBlobs(entry, path = []) {
  if (entry?.type === "blob") {
    return [{
      path: path.join("/"),
      content: Buffer.from(entry.base64, "base64").toString("utf8"),
    }];
  }
  if (entry?.type !== "tree" || !Array.isArray(entry.entries)) return [];
  return entry.entries.flatMap(([name, child]) =>
    summaryBlobs(child, [...path, name]));
}

function pendingSummaryCapture(evidence) {
  const blobs = summaryBlobs(evidence.tree);
  const schema = blobs.find(({ path }) =>
    path.endsWith("Schema/SchemaString"));
  const forest = blobs.filter(({ path }) =>
    path.startsWith("Forest/") || path.includes("/Forest/"));
  assert(schema, "Pending writer summary encoding lacks the schema blob");
  assert(forest.length > 0, "Pending writer summary encoding lacks forest blobs");
  return {
    sequenceNumber: evidence.sequenceNumber,
    schema,
    forest,
  };
}

function sameBlobContents(left, right) {
  return [...left].map(({ content }) => content).sort()
    .every((content, index) =>
      content === [...right].map(({ content }) => content).sort()[index])
    && left.length === right.length;
}

function historyContains(history, accepted, kind) {
  return history.trunk.some((entry) => {
    const commit = entry.commit ?? entry;
    if (commit.changeset?.changeCount <= 0) return false;
    if (commit.originatorId !== null && commit.originatorId !== undefined
      && commit.originatorId !== accepted.originatorId) return false;
    try {
      const decoded = decodeReconnectPayload(commit.changeset.raw);
      return decoded.kind === kind
        && isDeepStrictEqual(decoded, decodeReconnectPayload(accepted.changeset));
    } catch {
      return false;
    }
  });
}

function textualHistoryChanges(raw, label) {
  assert(/^Changeset\(/.test(raw),
    `${label} contains an invalid operation`);
  const start = raw.indexOf("[");
  assert(start >= 0, `${label} contains an invalid operation`);
  let depth = 0;
  let quoted = false;
  let escaped = false;
  let end = -1;
  for (let index = start; index < raw.length; index += 1) {
    const character = raw[index];
    if (quoted) {
      const wasEscaped = escaped;
      if (character === "\"" && !wasEscaped) quoted = false;
      escaped = character === "\\" && !wasEscaped;
      continue;
    }
    if (character === "\"") {
      quoted = true;
    } else if (character === "[") {
      depth += 1;
    } else if (character === "]") {
      depth -= 1;
      if (depth === 0) {
        end = index;
        break;
      }
    }
  }
  assert(end >= 0 && /^\s*\)$/.test(raw.slice(end + 1)),
    `${label} contains an invalid operation`);
  const body = raw.slice(start + 1, end).trim();
  if (body.length === 0) return [];
  const changes = [];
  let changeStart = 0;
  depth = 0;
  quoted = false;
  escaped = false;
  for (let index = 0; index <= body.length; index += 1) {
    const character = body[index];
    if (quoted) {
      const wasEscaped = escaped;
      if (character === "\"" && !wasEscaped) quoted = false;
      escaped = character === "\\" && !wasEscaped;
      continue;
    }
    if (character === "\"") {
      quoted = true;
    } else if (character !== undefined && "([{".includes(character)) {
      depth += 1;
    } else if (character !== undefined && ")]}".includes(character)) {
      depth -= 1;
    } else if ((character === "," && depth === 0)
      || character === undefined) {
      changes.push(body.slice(changeStart, index).trim());
      changeStart = index + 1;
    }
  }
  assert(changes.every((change) => /^(?:SchemaChange|DataChange)\(/.test(change)),
    `${label} contains an invalid operation`);
  return changes;
}

function decodeHistoryOperation(raw, label) {
  try {
    return decodeReconnectPayload(raw);
  } catch (error) {
    assert.fail(`${label} contains an invalid operation: ${error.message}`);
  }
}

function historyOperations(changeset, label) {
  assert(Number.isSafeInteger(changeset?.changeCount)
    && changeset.changeCount > 0,
  `${label} contains an empty operation`);
  const raw = changeset.payload ?? changeset.raw;
  let encoded;
  let textual = false;
  if (typeof raw === "string") {
    try {
      encoded = JSON.parse(raw);
    } catch {
      encoded = textualHistoryChanges(raw, label);
      textual = true;
    }
  } else {
    encoded = raw;
  }
  const changes = textual
    ? encoded
    : Array.isArray(encoded)
      ? encoded
      : encoded?.changes ?? encoded?.changeset;
  assert(Array.isArray(changes) && changes.length > 0,
    `${label} contains an empty operation`);
  assert.equal(changes.length, changeset.changeCount,
    `${label} contains a mismatched operation count`);
  return changes.map((change) => decodeHistoryOperation(
    textual ? `Changeset([${change}])` : [change],
    label,
  ));
}

function schemaFields(schema) {
  if (!schema || typeof schema !== "object") return new Set();
  const fields = new Set();
  for (const [, node] of schema.nodes ?? []) {
    if (node?.kind !== "object") continue;
    for (const [name] of node.fields ?? []) fields.add(name);
  }
  return fields;
}

function validatePostUpgradeHistory(history, upgrade, label) {
  const decodedUpgrade = decodeReconnectPayload(upgrade.changeset);
  assert.equal(decodedUpgrade.kind, "schema",
    `${label} lacks the expected schema upgrade`);
  const oldFields = schemaFields(decodedUpgrade.old);
  const addedFields = new Set(
    [...schemaFields(decodedUpgrade.new)].filter((field) => !oldFields.has(field)),
  );
  const operations = [];
  for (const entry of history.trunk) {
    const commit = entry.commit ?? entry;
    operations.push(...historyOperations(commit.changeset, label));
  }
  assert(operations.some((operation) =>
    isDeepStrictEqual(operation, decodedUpgrade)
      || (operation.kind === "data" && addedFields.has(operation.field))),
  `${label} lacks an upgrade-bearing operation`);
}

function pendingSummaryBinding(capture, reference, upgraded) {
  assert.equal(capture.sequenceNumber, reference.sequenceNumber,
    "Pending encoder reference does not identify the captured sequenced state");
  assert(capture.sequenceNumber < upgraded.sequenceNumber,
    "Pending encoder capture did not precede the sequenced upgrade");
  assert.deepEqual(JSON.parse(capture.schema.content),
    JSON.parse(reference.schema.content),
  "Pending encoder schema differs from sequenced state at capture");
  assert(sameBlobContents(capture.forest, reference.forest),
    "Pending encoder forest differs from sequenced state at capture");
  return {
    schema: "sequenced-at-capture",
    forest: "sequenced-at-capture",
    captureSequenceNumber: capture.sequenceNumber,
    upgradeSequenceNumber: upgraded.sequenceNumber,
  };
}

async function within(promise, label, milliseconds = 60_000) {
  let timer;
  try {
    return await Promise.race([
      promise,
      new Promise((_resolve, reject) => {
        timer = setTimeout(() => reject(new Error(`Timed out: ${label}`)), milliseconds);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

function retainedMoveIdentity(history) {
  assert(Array.isArray(history) && history.length > 0,
    "Array reload lacks retained summary history");
  const endpoints = { moveOut: [], moveIn: [] };
  function collect(value, revision) {
    if (Array.isArray(value)) {
      for (const item of value) collect(item, revision);
      return;
    }
    if (!value || typeof value !== "object") return;
    for (const [key, item] of Object.entries(value)) {
      if (key === "moveOut" || key === "moveIn") {
        assert(Number.isSafeInteger(item?.id),
          "Retained move endpoint lacks an atom ID");
        const endpointRevision = item.revision ?? revision;
        assert(Number.isSafeInteger(endpointRevision),
          "Retained move endpoint lacks a revision");
        endpoints[key].push({ id: item.id, revision: endpointRevision });
      }
      collect(item, revision);
    }
  }
  const moves = history.filter((entry) => {
    const before = endpoints.moveOut.length + endpoints.moveIn.length;
    collect(entry.changes, entry.revision);
    return endpoints.moveOut.length + endpoints.moveIn.length > before;
  });
  assert.equal(moves.length, 1, "Array reload lacks one retained move commit");
  const [move] = moves;
  return {
    revision: move.revision,
    originatorId: move.originatorId,
    ...endpoints,
  };
}

function submissionHistory(submission) {
  return submission.commits.map(({ revision, originatorId, changeset }) => ({
    revision,
    originatorId,
    changes: [changeset],
  }));
}

function retainedDeletedPoint(entry) {
  if (!Array.isArray(entry)) return false;
  const node = entry[2];
  if (!node || typeof node !== "object") return false;
  if (node.type === "org.watershed.shared-tree.m3.Point") {
    return node.fields?.label?.[0]?.value === "deleted"
      && node.fields?.x?.[0]?.value === 9;
  }
  if (node.kind !== "object"
    || node.schemaId !== "org.watershed.shared-tree.m3.Point"
    || !Array.isArray(node.fields)) return false;
  const fields = Object.fromEntries(node.fields);
  return fields.label?.value === "deleted" && fields.x?.value === 9;
}

async function observed(predicate, label) {
  await within((async () => {
    while (!await predicate()) await delay(25);
  })(), label);
}

async function cleanupAll(primaryError, label, actions) {
  const cleanupErrors = [];
  for (const action of actions) {
    try {
      await action();
    } catch (error) {
      cleanupErrors.push(error);
    }
  }
  if (cleanupErrors.length === 0) return;
  if (primaryError) {
    primaryError.cleanupErrors = [
      ...(primaryError.cleanupErrors ?? []),
      ...cleanupErrors,
    ];
  } else {
    throw new AggregateError(cleanupErrors, label);
  }
}

async function publishedVersion(config, document, jwt) {
  const url = `${config.httpUrl}/repos/${config.tenantId}/commits?sha=${document}&count=1`;
  const response = await fetch(url, { headers: { Authorization: `Bearer ${jwt}` } });
  assert.equal(response.status, 200, "Published version history is unavailable");
  const versions = await response.json();
  assert.equal(versions.length, 1, "Published version is missing");
  return versions[0].sha;
}

async function publishedSequence(config, document, jwt, version) {
  const base = `${config.httpUrl}/repos/${config.tenantId}/git`;
  async function object(url) {
    const response = await fetch(url, {
      headers: { Authorization: `Bearer ${jwt}` },
    });
    assert.equal(response.status, 200, `Cannot read published summary: ${url}`);
    return response.json();
  }
  const commit = await object(`${base}/commits/${version}`);
  let tree = await object(`${base}/trees/${commit.tree.sha}`);
  function child(source, name, type) {
    const entry = source.tree.find((value) => value.path === name);
    assert(entry && entry.type === type, `Published summary lacks ${name} ${type}`);
    return entry.sha;
  }
  const directProtocol = tree.tree.find(({ path, type }) =>
    path === ".protocol" && type === "tree");
  if (directProtocol) {
    tree = await object(`${base}/trees/${directProtocol.sha}`);
  } else {
    tree = await object(`${base}/trees/${child(tree, ".app", "tree")}`);
    tree = await object(`${base}/trees/${child(tree, ".protocol", "tree")}`);
  }
  const blob = await object(`${base}/blobs/${child(tree, "attributes", "blob")}`);
  assert(["base64", "utf-8"].includes(blob.encoding),
    "Protocol attributes use an unsupported encoding");
  const content = blob.encoding === "base64"
    ? Buffer.from(blob.content, "base64").toString("utf8")
    : blob.content;
  const attributes = JSON.parse(content);
  assert(Number.isSafeInteger(attributes.sequenceNumber)
    && attributes.sequenceNumber > 0, "Published snapshot has no sequence number");
  return attributes.sequenceNumber;
}

async function publishedSchemaSnapshot(config, document, jwt, version) {
  const base = `${config.httpUrl}/repos/${config.tenantId}/git`;
  async function object(path) {
    const response = await fetch(`${base}/${path}`, {
      headers: { Authorization: ["Bearer", jwt].join(" ") },
    });
    assert.equal(response.status, 200, `Cannot read published summary: ${path}`);
    return response.json();
  }
  const commit = await object(`commits/${version}`);
  const trees = [];
  const blobs = [];
  let schema;
  let forest;
  async function visit(treeId, path = []) {
    trees.push(treeId);
    const tree = await object(`trees/${treeId}`);
    for (const entry of tree.tree) {
      const entryPath = [...path, entry.path];
      if (entry.type === "tree") {
        if (entry.path === "Forest") {
          forest = {
            path: entryPath.join("/"),
            treeId: entry.sha,
            blobs: [],
          };
        }
        await visit(entry.sha, entryPath);
      } else if (entry.type === "blob") {
        blobs.push(entry.sha);
        if (entryPath.slice(-2).join("/") !== "Schema/SchemaString"
          && !entryPath.includes("Forest")) continue;
        const blob = await object(`blobs/${entry.sha}`);
        assert(["base64", "utf-8"].includes(blob.encoding),
          `Summary blob uses unsupported encoding: ${entryPath.join("/")}`);
        const content = blob.encoding === "base64"
          ? Buffer.from(blob.content, "base64").toString("utf8")
          : blob.content;
        const evidence = {
          path: entryPath.join("/"),
          id: entry.sha,
          byteLength: Buffer.byteLength(content),
          hash: createHash("sha256").update(content).digest("hex"),
          content,
        };
        if (entryPath.at(-2) === "Schema") schema = evidence;
        else forest?.blobs.push(evidence);
      }
    }
  }
  await visit(commit.tree.sha);
  assert(schema, "Selected summary lacks its stored schema blob");
  assert(forest?.blobs.length > 0, "Selected summary lacks its stored forest blobs");
  return {
    version,
    rootTreeId: commit.tree.sha,
    treeIds: trees,
    blobIds: blobs,
    schema,
    forest,
  };
}

async function publicationSequence(config, document, jwt, version, snapshot) {
  const pageSize = 64;
  const maximumMessages = 4096;
  let cursor = snapshot;
  const observedAcks = [];
  while (cursor - snapshot < maximumMessages) {
    const url = `${config.httpUrl}/deltas/${config.tenantId}/${document}`
      + `?from=${cursor}&to=${cursor + pageSize}`;
    const response = await fetch(url, {
      headers: { Authorization: `Bearer ${jwt}` },
    });
    assert.equal(response.status, 200, "Cannot read publication delta history");
    const { value: messages } = await response.json();
    assert(Array.isArray(messages) && messages.length > 0,
      `Publication acknowledgement is outside the available contiguous history: `
        + `snapshot=${snapshot} cursor=${cursor} version=${version} `
        + `acks=${JSON.stringify(observedAcks)}`);
    for (const message of messages) {
      assert.equal(message.sequenceNumber, cursor + 1,
        "Publication history has a gap or duplicate");
      cursor = message.sequenceNumber;
      const contents = typeof message.contents === "string"
        ? JSON.parse(message.contents) : message.contents;
      if (message.type === "summaryAck") {
        observedAcks.push({ sequenceNumber: cursor, contents });
      }
      if (message.type === "summaryAck" && contents?.handle === version) return cursor;
    }
  }
  assert.fail("No acknowledgement for the published checkpoint");
}

async function editJavascript(config, document, jwt, title, publish) {
  const probePath = join(repository,
    "build/dev/javascript/watershed/watershed/tree/summary_service_probe.mjs");
  const probe = await import(pathToFileURL(probePath));
  const socket = `${config.socketUrl.replace(/^http/, "ws")}/socket`;
  const result = await within(
    probe.edit_javascript(socket, document, jwt, title, publish),
    "native JavaScript edit",
  );
  assert(result.isOk(), `Native JavaScript edit failed: ${result[0]}`);
  return result[0];
}

async function editErlang(config, document, jwt, title, publish, auto = false) {
  const erlang = join(repository, "build/dev/erlang");
  const libraries = (await readdir(erlang, { withFileTypes: true }))
    .filter((entry) => entry.isDirectory())
    .map((entry) => join(erlang, entry.name, "ebin"));
  const endpoint = new URL(config.socketUrl);
  assert.equal(endpoint.protocol, "http:", "BEAM probe requires the local HTTP profile");
  const { stdout } = await execute("erl", [
    "-noshell", "-pa", ...libraries,
    "-eval", "{ok, _} = application:ensure_all_started(watershed), 'watershed@tree@summary_service_probe':main(), init:stop().",
  ], {
    cwd: repository,
    timeout: 90_000,
    env: {
      ...process.env,
      WATERSHED_TREE_HOST: endpoint.hostname,
      WATERSHED_TREE_PORT: endpoint.port,
      WATERSHED_TREE_DOCUMENT: document,
      WATERSHED_TREE_TOKEN: jwt,
      WATERSHED_TREE_TITLE: title,
      WATERSHED_TREE_PUBLISH: String(publish),
      WATERSHED_TREE_AUTO: String(auto),
      ERL_CRASH_DUMP: join(directory, ".output/summary-erl-crash.dump"),
    },
  }).catch((error) => {
    throw new Error(`BEAM publication probe failed: ${error.stdout}\n${error.stderr?.slice(0, 800)}`, {
      cause: error,
    });
  });
  const marker = publish ? "WATERSHED_TREE_VERSION=" : "WATERSHED_TREE_EDITED=";
  const results = stdout.split("\n").filter((line) => line.startsWith(marker));
  assert.equal(results.length, 1, "BEAM probe did not return exactly one outcome");
  return results[0].slice(marker.length);
}

async function reloadAndEdit(config, document, expectedTitle, title) {
  const containers = [];
  let reloadError;
  try {
    const reader = await within(openSession(config, containers, document),
      "upstream fresh summary reload");
    assert.equal(reader.data.view.root.title, expectedTitle);
    reader.data.view.root.title = title;
    await observed(() => !reader.container.isDirty, "upstream continuation acknowledgement");
    const peer = await within(openSession(config, containers, document),
      "upstream independent peer");
    assert.equal(peer.data.view.root.title, title);
    return true;
  } catch (error) {
    reloadError = error;
    throw error;
  } finally {
    await cleanupAll(reloadError, "Fresh summary reload cleanup failed",
      containers.toReversed().map((container) => () => container.dispose()));
  }
}

async function observeFreshUpstream(config, document, expectedTitle) {
  const containers = [];
  let observationError;
  try {
    const peer = await within(openSession(config, containers, document),
      "independent upstream peer");
    assert.equal(peer.data.view.root.title, expectedTitle);
    return true;
  } catch (error) {
    observationError = error;
    throw error;
  } finally {
    await cleanupAll(observationError, "Fresh upstream observation cleanup failed",
      containers.toReversed().map((container) => () => container.dispose()));
  }
}

export function validateResults(results) {
  const implementations = ["upstream", "javascript", "erlang"];
  assert(results && typeof results === "object" && !Array.isArray(results),
    "Summary interop needs a nested reload matrix");
  assert.deepEqual(Object.keys(results).sort(), [...implementations].sort(),
    "Summary interop needs all three writers");
  const readerInstances = new Set();
  for (const writer of implementations) {
    assert.deepEqual(Object.keys(results[writer] ?? {}).sort(), [...implementations].sort(),
      `Summary interop needs all three readers for ${writer}`);
    for (const reader of implementations) {
      const cell = results[writer][reader];
      assert.equal(cell.writer, writer, "Invalid writer identity");
      assert.equal(cell.reader, reader, "Invalid reader identity");
      assert(typeof cell.runId === "string" && cell.runId.length > 0,
        "Missing reload run ID");
      assert(typeof cell.profileDigest === "string"
        && /^[0-9a-f]{64}$/.test(cell.profileDigest),
      "Missing reload profile digest");
      assert(typeof cell.documentId === "string" && cell.documentId.length > 0,
        "Missing reload document ID");
    assert(typeof cell.writerVersion === "string" && cell.writerVersion.length > 0,
      "Missing published writer version");
      assert.equal(cell.loadedVersion, cell.writerVersion,
        "Reload selected another version");
      assert(typeof cell.readerInstanceId === "string"
        && cell.readerInstanceId.length > 0, "Missing fresh reader instance");
      assert(!readerInstances.has(cell.readerInstanceId), "Reload reused a reader instance");
      readerInstances.add(cell.readerInstanceId);
    assert(Number.isSafeInteger(cell.snapshotSequenceNumber)
      && cell.snapshotSequenceNumber >= 0
        && Number.isSafeInteger(cell.dataEditSequenceNumber)
        && cell.snapshotSequenceNumber < cell.dataEditSequenceNumber
      && Number.isSafeInteger(cell.publicationSequenceNumber)
        && cell.dataEditSequenceNumber < cell.publicationSequenceNumber,
    "Invalid snapshot/publication positions");
      assert(Number.isSafeInteger(cell.replayWatermark)
        && cell.replayWatermark >= cell.publicationSequenceNumber,
      "Missing replay watermark");
      assert(Number.isSafeInteger(cell.replayStartSequenceNumber)
        && cell.replayStartSequenceNumber >= cell.snapshotSequenceNumber,
      "Reload fell back to origin replay");
      assert(reader === "upstream"
        ? cell.replayEvidence === "upstream-delta-storage"
        : ["native-delivery", "native-handshake"].includes(cell.replayEvidence),
      "Reload lacks measured replay evidence");
      assert(Array.isArray(cell.selectedSummaryRequests)
        && cell.selectedSummaryRequests.includes(cell.loadedVersion),
      "Reload did not request the selected summary");
    assert(typeof cell.scenarioId === "string" && cell.scenarioId.length > 0,
      "Missing persistence scenario");
    assert.equal(cell.loaded, true);
    assert.equal(cell.continuedEditing, true);
    assert.equal(cell.peerObservedEdit, true);
      assert.equal(cell.pendingTreeCount, 0);
      assert.equal(cell.inflightSubmissionCount, 0);
      assert(cell.wholeTree && typeof cell.wholeTree === "object",
        "Missing typed root observation");
      assert(cell.retained && typeof cell.retained === "object",
        "Missing retained-state observation");
      assert.deepEqual(cell.retained.visible, { x: 3, y: 4 },
        "Reload changed the visible replacement point");
      assert.deepEqual(cell.retained.detached, { x: 42, y: 7 },
        "Reload restored the wrong detached point");
      assert.deepEqual(restoredDetachedPoint(cell.retained.removed), { x: 42, y: 7 },
        "Reload removed content lacks the retained detached point");
      assert.equal(cell.retained.summaryConsumed, true,
        "Retained-state verifier did not consume the summary");
      assert.equal(cell.retained.upstreamSelectedVersion, cell.writerVersion,
        "Retained-state verifier selected another summary");
      assert(Array.isArray(cell.retained.writerIdentity?.clientIds)
        && cell.retained.writerIdentity.clientIds.length > 0,
      "Retained-state writer lacks client identity");
      assert(Array.isArray(cell.retained.writerIdentity?.originatorIds)
        && cell.retained.writerIdentity.originatorIds.length === 1,
      "Retained-state writer lacks compressor identity");
      if (writer !== "upstream") {
        assert.deepEqual(
          cell.retained.writerIdentity.resubmissions.map(({ refresher }) => refresher),
          [[1, 2], [42, 2]],
          "Native retained-state refreshers changed",
        );
      }
      assert(Array.isArray(cell.artifacts) && cell.artifacts.length > 0,
        "Missing reload artifact");
    }
  }
  return results;
}

export function validateIdentifierReloadResults(results) {
  assert(results && typeof results === "object" && !Array.isArray(results),
    "Identifier summary interop needs a nested reload matrix");
  assert.deepEqual(Object.keys(results).sort(), [...implementations].sort(),
    "Identifier summary interop needs all three writers");
  const readerInstances = new Set();
  for (const writer of implementations) {
    assert.deepEqual(Object.keys(results[writer] ?? {}).sort(), [...implementations].sort(),
      `Identifier summary interop needs all three readers for ${writer}`);
    for (const reader of implementations) {
      const cell = results[writer][reader];
      assert.equal(cell.profile, "identifier", "Identifier reload has another profile");
      assert.equal(cell.writer, writer, "Invalid Identifier writer identity");
      assert.equal(cell.reader, reader, "Invalid Identifier reader identity");
      assert(typeof cell.runId === "string" && cell.runId.length > 0,
        "Missing Identifier reload run ID");
      assert.match(cell.profileDigest, /^[0-9a-f]{64}$/,
        "Missing Identifier reload profile digest");
      assert(typeof cell.documentId === "string" && cell.documentId.length > 0,
        "Missing Identifier reload document ID");
      assert(typeof cell.writerVersion === "string" && cell.writerVersion.length > 0,
        "Missing Identifier writer version");
      assert.equal(cell.loadedVersion, cell.writerVersion,
        "Identifier reload selected another version");
      assert(typeof cell.readerInstanceId === "string"
        && cell.readerInstanceId.length > 0, "Missing Identifier reader instance");
      assert(!readerInstances.has(cell.readerInstanceId),
        "Identifier reload reused a reader instance");
      readerInstances.add(cell.readerInstanceId);
      assert.equal(cell.scenarioId, "identifier-summary-postload");
      assert.equal(cell.loaded, true);
      assert(typeof cell.writerAuthored?.defaultId === "string"
        && cell.writerAuthored.defaultId.length > 0,
      "Identifier writer lacks a generated ID");
      assert.equal(cell.writerAuthored.explicitId, "shared-custom-id",
        "Identifier writer changed the explicit ID");
      assert.equal(cell.postLoadAuthored?.author, reader,
        "Identifier reader did not author the post-load node");
      assert(typeof cell.postLoadAuthored.id === "string"
        && cell.postLoadAuthored.id.length > 0,
      "Identifier reader lacks a post-load ID");
      assert(typeof cell.postLoadAuthored.originatorId === "string"
        && cell.postLoadAuthored.originatorId.length > 0,
      "Identifier post-load edit lacks an originator");
      assert(typeof cell.postLoadAuthored.allocationRange?.sessionId === "string"
        && Number.isSafeInteger(cell.postLoadAuthored.allocationRange?.ids?.first)
        && Number.isSafeInteger(cell.postLoadAuthored.allocationRange?.ids?.count)
        && cell.postLoadAuthored.allocationRange.ids.count > 0,
      "Identifier post-load edit lacks its allocation range");
      assert.equal(cell.peerObservation?.observed, true,
        "Identifier post-load edit lacks peer observation");
      assert.equal(cell.peerObservation.id, cell.postLoadAuthored.id,
        "Identifier peer observed another ID");
      assert(implementations.includes(cell.peerObservation.implementation),
        "Identifier peer has another implementation");
      assert.equal(cell.pendingTreeCount, 0);
      assert.equal(cell.inflightSubmissionCount, 0);
      assert(Array.isArray(cell.artifacts) && cell.artifacts.length > 0,
        "Missing Identifier reload artifact");
    }
  }
  return results;
}

export function validateMapResults(results) {
  assert(results && typeof results === "object" && !Array.isArray(results),
    "Map summary interop needs a nested reload matrix");
  assert.deepEqual(Object.keys(results).sort(), [...implementations].sort(),
    "Map summary interop needs all three writers");
  const readerInstances = new Set();
  for (const writer of implementations) {
    assert.deepEqual(Object.keys(results[writer] ?? {}).sort(), [...implementations].sort(),
      `Map summary interop needs all three readers for ${writer}`);
    for (const reader of implementations) {
      const cell = results[writer][reader];
      assert.equal(cell.profile, "map", "Map reload has another profile");
      assert.equal(cell.writer, writer, "Invalid map writer identity");
      assert.equal(cell.reader, reader, "Invalid map reader identity");
      assert(typeof cell.runId === "string" && cell.runId.length > 0,
        "Missing map reload run ID");
      assert(typeof cell.profileDigest === "string"
        && /^[0-9a-f]{64}$/.test(cell.profileDigest),
      "Missing map reload profile digest");
      assert(typeof cell.documentId === "string" && cell.documentId.length > 0,
        "Missing map reload document ID");
      assert(typeof cell.writerVersion === "string" && cell.writerVersion.length > 0,
        "Missing map writer version");
      assert.equal(cell.loadedVersion, cell.writerVersion,
        "Map reload selected another version");
      assert(typeof cell.readerInstanceId === "string"
        && cell.readerInstanceId.length > 0, "Missing fresh map reader instance");
      assert(!readerInstances.has(cell.readerInstanceId),
        "Map reload reused a reader instance");
      readerInstances.add(cell.readerInstanceId);
      assert(Number.isSafeInteger(cell.snapshotSequenceNumber)
        && cell.snapshotSequenceNumber >= 0
        && Number.isSafeInteger(cell.dataEditSequenceNumber)
        && cell.snapshotSequenceNumber < cell.dataEditSequenceNumber
        && Number.isSafeInteger(cell.publicationSequenceNumber)
        && cell.dataEditSequenceNumber < cell.publicationSequenceNumber,
      "Invalid map snapshot/publication positions");
      assert(Number.isSafeInteger(cell.replayWatermark)
        && cell.replayWatermark >= cell.publicationSequenceNumber,
      "Missing map replay watermark");
      assert(Number.isSafeInteger(cell.replayStartSequenceNumber)
        && cell.replayStartSequenceNumber >= cell.snapshotSequenceNumber,
      "Map reload fell back to origin replay");
      assert(reader === "upstream"
        ? cell.replayEvidence === "upstream-delta-storage"
        : ["native-delivery", "native-handshake"].includes(cell.replayEvidence),
      "Map reload lacks measured replay evidence");
      assert(Array.isArray(cell.selectedSummaryRequests)
        && cell.selectedSummaryRequests.includes(cell.loadedVersion),
      "Map reload did not request the selected summary");
      assert.equal(cell.scenarioId, "map-summary-tail-retained");
      assert.equal(cell.loaded, true);
      assert.equal(cell.tailObserved, true);
      assert.equal(cell.continuedEditing, true);
      assert.equal(cell.peerObservedEdit, true);
      assert.equal(cell.deletedEntryAbsent, true);
      assert.equal(cell.pendingTreeCount, 0);
      assert.equal(cell.inflightSubmissionCount, 0);
      assert.deepEqual(cell.wholeTree, canonicalValue(cell.wholeTree),
        "Map reload entries are not canonical");
      assert(Array.isArray(cell.retained?.removed)
        && cell.retained.removed.length > 0,
      "Map reload lacks retained deleted content");
      assert.equal(cell.retained.deletedKey, "deleted",
        "Map reload retained another deleted key");
      assert.equal(cell.retained.summaryConsumed, true,
        "Map retained-state verifier did not consume the summary");
      assert(Array.isArray(cell.artifacts) && cell.artifacts.length > 0,
        "Missing map reload artifact");
    }
  }
  return results;
}

export function validateArrayResults(results) {
  assert(results && typeof results === "object" && !Array.isArray(results),
    "Array summary interop needs a nested reload matrix");
  assert.deepEqual(Object.keys(results).sort(), [...implementations].sort(),
    "Array summary interop needs all three writers");
  const readerInstances = new Set();
  for (const writer of implementations) {
    assert.deepEqual(Object.keys(results[writer] ?? {}).sort(),
      [...implementations].sort(),
    `Array summary interop needs all three readers for ${writer}`);
    for (const reader of implementations) {
      const cell = results[writer][reader];
      assert.equal(cell.profile, "array", "Array reload has another profile");
      assert.equal(cell.writer, writer, "Invalid array writer identity");
      assert.equal(cell.reader, reader, "Invalid array reader identity");
      assert(typeof cell.runId === "string" && cell.runId.length > 0,
        "Missing array reload run ID");
      assert.match(cell.profileDigest, /^[0-9a-f]{64}$/,
        "Missing array reload profile digest");
      assert(typeof cell.documentId === "string" && cell.documentId.length > 0,
        "Missing array reload document ID");
      assert(typeof cell.writerVersion === "string" && cell.writerVersion.length > 0,
        "Missing array writer version");
      assert.equal(cell.loadedVersion, cell.writerVersion,
        "Array reload selected another version");
      assert(typeof cell.readerInstanceId === "string"
        && cell.readerInstanceId.length > 0, "Missing fresh array reader instance");
      assert(!readerInstances.has(cell.readerInstanceId),
        "Array reload reused a reader instance");
      readerInstances.add(cell.readerInstanceId);
      assert(Number.isSafeInteger(cell.snapshotSequenceNumber)
        && Number.isSafeInteger(cell.dataEditSequenceNumber)
        && Number.isSafeInteger(cell.publicationSequenceNumber)
        && Number.isSafeInteger(cell.tailSequenceNumber)
        && cell.snapshotSequenceNumber < cell.dataEditSequenceNumber
        && cell.dataEditSequenceNumber < cell.publicationSequenceNumber
        && cell.publicationSequenceNumber < cell.tailSequenceNumber,
      "Array reload has invalid summary and tail sequencing");
      assert(Number.isSafeInteger(cell.replayStartSequenceNumber)
        && cell.replayStartSequenceNumber >= cell.snapshotSequenceNumber,
      "Array reload fell back to origin replay");
      assert(reader === "upstream"
        ? cell.replayEvidence === "upstream-delta-storage"
        : ["native-delivery", "native-handshake"].includes(cell.replayEvidence),
      "Array reload lacks measured replay evidence");
      assert(Array.isArray(cell.selectedSummaryRequests)
        && cell.selectedSummaryRequests.includes(cell.loadedVersion),
      "Array reload did not request the selected summary");
      assert.equal(cell.scenarioId, "array-summary-tail-retained");
      assert.equal(cell.loaded, true);
      assert.equal(cell.tailObserved, true);
      assert.equal(cell.continuedEditing, true);
      assert.equal(cell.peerObservedEdit, true);
      assert.equal(cell.pendingTreeCount, 0);
      assert.equal(cell.inflightSubmissionCount, 0);
      assert.deepEqual(cell.wholeTree, expectedArrayTree(writer),
        "Array reload loaded another tagged tree");
      assert(typeof cell.continuationLabel === "string"
        && cell.continuationLabel.startsWith(`${writer}-${reader}-`),
      "Array reload lacks the exact continuation label");
      assert.deepEqual(cell.continuationTree,
        expectedArrayTree(writer, cell.continuationLabel),
        "Array reload continuation has another value or order");
      assert.deepEqual(cell.continuationTree, cell.peerWholeTree,
        "Array reload continuation differs from the independent peer");
      assert(Array.isArray(cell.retained?.removed)
        && cell.retained.removed.length > 0,
      "Array reload lacks retained deleted content");
      assert(cell.retained.removed.some(retainedDeletedPoint),
        "Array reload retained the wrong deleted content");
      assert.equal(cell.retained.selectedVersion, cell.loadedVersion,
        "Array reload retained content came from another summary");
      assert.equal(cell.retained.reader, reader,
        "Array reload retained evidence came from another reader");
      assert.equal(cell.retained.readerInstanceId, cell.readerInstanceId,
        "Array reload retained evidence came from another reader instance");
      assert.equal(cell.retained.source, reader === "upstream"
        ? "upstream-runtime-and-wire"
        : "native-runtime-snapshot",
      "Array reload retained evidence has another source");
      assert.equal(cell.retained.loadedVersion, cell.loadedVersion,
        "Array reload retained evidence has another loaded version");
      assert.equal(cell.retained.snapshotSequenceNumber, cell.snapshotSequenceNumber,
        "Array reload retained evidence has another snapshot sequence");
      assert(Number.isSafeInteger(cell.retained.sequenceNumber)
        && cell.retained.sequenceNumber >= cell.snapshotSequenceNumber
        && cell.retained.sequenceNumber <= cell.replayWatermark,
      "Array reload retained evidence is outside the loaded snapshot sequence");
      assert(Array.isArray(cell.retained.history)
        && cell.retained.history.length > 0,
      "Array reload lacks retained summary history");
      const moveIdentity = cell.retained.moveIdentity;
      assert.deepEqual(moveIdentity, retainedMoveIdentity(cell.retained.history),
        "Array reload move identity differs from retained summary history");
      assert(Number.isSafeInteger(moveIdentity?.revision)
        && typeof moveIdentity.originatorId === "string"
        && moveIdentity.originatorId.length > 0
        && Array.isArray(moveIdentity.moveOut)
        && moveIdentity.moveOut.length === 1
        && Array.isArray(moveIdentity.moveIn)
        && moveIdentity.moveIn.length === 1,
      "Array reload lacks persisted move identity");
      const [moveOut] = moveIdentity.moveOut;
      const [moveIn] = moveIdentity.moveIn;
      assert(Number.isSafeInteger(moveOut.id)
        && Number.isSafeInteger(moveOut.revision)
        && Number.isSafeInteger(moveIn.id)
        && Number.isSafeInteger(moveIn.revision)
        && moveOut.id === moveIn.id
        && moveOut.revision === moveIdentity.revision
        && moveIn.revision === moveIdentity.revision,
      "Array reload has invalid persisted move atoms");
      assert.equal(cell.retained.childEditObserved, true,
        "Array reload lacks the moved-child edit proof");
      assert.equal(cell.retained.summaryConsumed, true,
        "Array retained-state verifier did not consume the summary");
      const continuation = cell.continuationIdentity;
      assert(typeof continuation?.clientId === "string"
        && Number.isSafeInteger(continuation.referenceSequenceNumber)
        && Array.isArray(continuation.revisions)
        && continuation.revisions.length > 0,
      "Array reload lacks continuation identity");
      assert(Array.isArray(cell.artifacts) && cell.artifacts.length > 0,
        "Missing array reload artifact");
    }
  }
  return results;
}

function validateFocusedResults(results) {
  const requiredPairs = implementations.flatMap((writer) =>
    implementations.map((reader) => `${writer}->${reader}`));
  assert(Array.isArray(results) && results.length === requiredPairs.length,
    "Focused summary interop needs exactly nine persistence cells");
  for (const cell of results) {
    assert(implementations.includes(cell.writer), "Invalid writer identity");
    assert(implementations.includes(cell.reader), "Invalid reader identity");
    assert(typeof cell.writerVersion === "string" && cell.writerVersion.length > 0,
      "Missing published writer version");
    assert(Number.isSafeInteger(cell.snapshotSequenceNumber)
      && Number.isSafeInteger(cell.publicationSequenceNumber)
      && cell.publicationSequenceNumber >= cell.snapshotSequenceNumber,
    "Invalid snapshot/publication positions");
    assert.equal(cell.loaded, true);
    assert.equal(cell.continuedEditing, true);
    assert.equal(cell.peerObservedEdit, true);
  }
  assert.deepEqual(
    [...new Set(results.map(({ writer, reader }) => `${writer}->${reader}`))].sort(),
    requiredPairs.sort(),
  );
  return results;
}

function validateEntry(value) {
  assert(value && typeof value === "object" && !Array.isArray(value),
    "Invalid summary entry");
  if (value.type === "blob") {
    assert(typeof value.base64 === "string"
      && Buffer.from(value.base64, "base64").toString("base64") === value.base64,
    "Invalid summary blob encoding");
    return;
  }
  assert.equal(value.type, "tree", "Unresolved or unsupported summary entry");
  assert(Array.isArray(value.entries), "Summary tree has no entries");
  const names = new Set();
  for (const entry of value.entries) {
    assert(Array.isArray(entry) && entry.length === 2
      && typeof entry[0] === "string" && entry[0].length > 0,
    "Invalid summary tree path");
    assert(!names.has(entry[0]), `Duplicate summary path: ${entry[0]}`);
    names.add(entry[0]);
    validateEntry(entry[1]);
  }
}

function retainsSchemaContext(
  value, underEditManager = false, underSchemaIndex = false,
) {
  if (value.type === "blob") {
    try {
      const decoded = JSON.parse(Buffer.from(value.base64, "base64").toString("utf8"));
      if (underSchemaIndex) {
        return decoded?.nodes && typeof decoded.nodes === "object"
          && decoded?.root && typeof decoded.root === "object";
      }
      if (underEditManager) {
        const commits = [
          ...(decoded.trunk ?? []),
          ...(decoded.branches ?? []).flatMap((branch) => branch?.[1]?.commits ?? []),
        ];
        return commits.some((commit) =>
          Array.isArray(commit.change)
          && commit.change.some((change) => change?.schema));
      }
      return false;
    } catch {
      return false;
    }
  }
  return value.entries.some(([name, entry]) =>
    retainsSchemaContext(
      entry,
      underEditManager || name === "EditManager",
      underSchemaIndex || name === "Schema",
    ));
}

export function validateSummaryArtifact(output, target, cases = persistenceStates) {
  assert(output?.target === target, "Wrong summary artifact target");
  assert.deepEqual(output.reference, identity, "Stale summary reference");
  assert(Array.isArray(output.cases) && output.cases.length === cases.length
    && cases.length > 0, "Missing summary artifact cases");
  const actual = [];
  for (const item of output.cases) {
    assert(typeof item.id === "string" && item.id.length > 0,
      "Missing summary scenario ID");
    actual.push(item.id);
    assert(Number.isSafeInteger(item.snapshotSequenceNumber)
      && item.snapshotSequenceNumber >= 0
      && Number.isSafeInteger(item.publicationSequenceNumber)
      && item.publicationSequenceNumber >= item.snapshotSequenceNumber,
    "Invalid summary sequence positions");
    validateEntry(item.tree);
    assert(item.tree.entries.length > 0, "Empty summary hierarchy");
    assert(retainsSchemaContext(item.tree),
      "Summary artifact lacks retained schema context");
  }
  assert.deepEqual(actual, cases, "Missing, repeated, or reordered summary scenarios");
  return output;
}

async function produceSummary(target, path, inputPath) {
  await execute("gleam", ["run", "--target", target, "-m", "watershed/tree/summary_export"], {
    cwd: repository,
    timeout: 120_000,
    env: {
      ...process.env,
      WATERSHED_TREE_SUMMARY_INPUT: inputPath,
      WATERSHED_TREE_SUMMARY_OUTPUT: path,
      WATERSHED_TREE_SUMMARY_TARGET: target,
    },
  });
}

async function checkSplitMap(owned) {
  const environment = makeEnvironment();
  const document = `split-map-${randomUUID()}`;
  const large = "a".repeat(9 * 1024);
  let splitMapError;
  try {
    const writer = await environment.open(document, { create: true });
    writer.data.bootstrap.set("large", large);
    await observed(() => !writer.container.isDirty, "upstream large map acknowledgement");
    await publishSummary(environment, document, "split SharedMap blob");
    const snapshot = await readSnapshot(environment, writer.container.resolvedUrl);
    const map = snapshot.tree.trees[".channels"]?.trees.A
      ?.trees[".channels"]?.trees.root;
    assert(map, "Upstream summary has no bootstrap SharedMap");
    const header = JSON.parse(Buffer.from(
      snapshot.blobs[map.blobs.header], "base64",
    ).toString("utf8"));
    assert(header.blobs.includes("blob0"), "Upstream did not split the 9KiB map value");
    assert.equal(typeof snapshot.blobs[map.blobs.blob0], "string",
      "Upstream split map value is missing");
    const input = join(owned, "large-map.json");
    await writeFile(input, JSON.stringify(snapshot));
    for (const target of ["javascript", "erlang"]) {
      await execute("gleam", [
        "run", "--target", target, "-m", "watershed/tree/summary_map_probe",
      ], {
        cwd: repository,
        timeout: 120_000,
        env: {
          ...process.env,
          WATERSHED_TREE_MAP_SNAPSHOT: input,
          WATERSHED_TREE_MAP_VALUE: large,
        },
      });
    }
    return { targets: ["javascript", "erlang"], size: large.length };
  } catch (error) {
    splitMapError = error;
    throw error;
  } finally {
    await cleanupAll(splitMapError, "Split-map environment cleanup failed",
      [() => environment.close()]);
  }
}

function upstreamSummary(entry) {
  if (entry.type === "blob") {
    const bytes = Buffer.from(entry.base64, "base64");
    const content = bytes.toString("utf8");
    assert(Buffer.from(content).equals(bytes), "Native artifact contains a non-UTF-8 blob");
    return { type: SummaryType.Blob, content };
  }
  assert.equal(entry.type, "tree", "Unsupported native summary entry");
  return {
    type: SummaryType.Tree,
    tree: Object.fromEntries(entry.entries.map(([name, child]) =>
      [name, upstreamSummary(child)])),
  };
}

async function consumeRetainedArtifact(environment, output, target) {
  const results = [];
  for (const id of ["concurrent-detached", "after-peer-leave", "after-nontree-tail"]) {
    const native = output.cases.find((item) => item.id === id);
    assert(native, `${target} omitted ${id}`);
    const document = `native-${target}-${id}-${randomUUID()}`;
    const url = await environment.urlResolver.resolve({
      url: `http://localhost:3000/${document}`,
    });
    const snapshot = upstreamSummary(native.tree);
    const protocol = snapshot.tree[".protocol"];
    assert(protocol, `${target} ${id} omitted protocol`);
    delete snapshot.tree[".protocol"];
    const service = await environment.documentServiceFactory.createContainer(
      { type: SummaryType.Tree, tree: { ".protocol": protocol, ".app": snapshot } }, url,
    );
    service.dispose();
    const sessions = [];
    let retainedError;
    try {
      const reader = await environment.open(document);
      sessions.push(reader);
      assert.equal(reader.data.view.root.rating,
        { "concurrent-detached": 2, "after-peer-leave": 3, "after-nontree-tail": 4 }[id],
        `${target} ${id} did not restore the native tree root`);
      const next = native.publicationSequenceNumber + 1000;
      reader.data.view.root.rating = next;
      await observed(() => !reader.container.isDirty,
        `${target} ${id} post-restore edit acknowledgement`);
      const peer = await environment.open(document);
      sessions.push(peer);
      await observed(() => peer.data.view.root.rating === next,
        `${target} ${id} independent peer continuation`);
      results.push({ target, id, loaded: true, authored: next, peerObserved: true });
    } catch (error) {
      retainedError = error;
      throw error;
    } finally {
      await cleanupAll(retainedError, `${target} ${id} retained cleanup failed`,
        sessions.toReversed().map((session) => () => environment.dispose(session)));
    }
  }
  return results;
}

export async function runArtifactInterop({
  produce = produceSummary, cases = persistenceStates,
} = {}) {
  const owned = await mkdtemp(join(tmpdir(), "watershed-summary-interop-"));
  const input = join(repository, "test/fixtures/shared_tree/cases/summary-writer-matrix.json");
  let interopError;
  try {
    const results = [];
    const retained = [];
    const environment = makeEnvironment();
    let environmentError;
    try {
      for (const target of ["javascript", "erlang"]) {
        const path = join(owned, `${target}.json`);
        await produce(target, path, input);
        let output;
        try {
          output = JSON.parse(await readFile(path, "utf8"));
        } catch (error) {
          throw new Error(`Missing or invalid ${target} summary artifact: ${path}`, {
            cause: error,
          });
        }
        validateSummaryArtifact(output, target, cases);
        if (cases === persistenceStates) {
          retained.push(...await consumeRetainedArtifact(environment, output, target));
        }
        results.push({
          target, caseCount: output.cases.length,
          scenarios: output.cases.map(({ id, snapshotSequenceNumber,
            publicationSequenceNumber }) => ({
            id, snapshotSequenceNumber, publicationSequenceNumber,
          })),
        });
      }
    } catch (error) {
      environmentError = error;
      throw error;
    } finally {
      await cleanupAll(environmentError, "Summary environment cleanup failed",
        [() => environment.close()]);
    }
    const splitMap = await checkSplitMap(owned);
    return { reference: identity, targets: results, retained, splitMap };
  } catch (error) {
    interopError = error;
    throw error;
  } finally {
    await cleanupAll(interopError, "Summary artifact cleanup failed",
      [() => rm(owned, { recursive: true, force: true })]);
  }
}

function reloadMeasuredPayload(item) {
  return Object.fromEntries(Object.entries(item)
    .filter(([name]) => name !== "artifacts"));
}

async function writeReloadArtifact(context, item, raw) {
  const relative = `reload/${item.writer}-${item.reader}.json`;
  const path = join(context.artifactDirectory, relative);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify({
    formatVersion: 1,
    runId: context.runId,
    profileDigest: context.profileDigest,
    kind: "reload",
    subject: `${item.writer}->${item.reader}`,
    documentId: item.documentId,
    measured: reloadMeasuredPayload(item),
    raw,
  })}\n`, { mode: 0o600 });
  return relative;
}

async function writeMapReloadArtifact(context, item, raw) {
  const relative = `map-reload/${item.writer}-${item.reader}.json`;
  const path = join(context.artifactDirectory, relative);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify({
    formatVersion: 1,
    runId: context.runId,
    profileDigest: context.profileDigest,
    kind: "map-reload",
    subject: `${item.writer}->${item.reader}`,
    documentId: item.documentId,
    measured: reloadMeasuredPayload(item),
    raw,
  })}\n`, { mode: 0o600 });
  return relative;
}

async function writeArrayReloadArtifact(context, item, raw) {
  const relative = `array-reload/${item.writer}-${item.reader}.json`;
  const path = join(context.artifactDirectory, relative);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify({
    formatVersion: 1,
    runId: context.runId,
    profileDigest: context.profileDigest,
    kind: "array-reload",
    subject: `${item.writer}->${item.reader}`,
    documentId: item.documentId,
    measured: reloadMeasuredPayload(item),
    raw,
  })}\n`, { mode: 0o600 });
  return relative;
}
function storageResponseBytes(observation, hash) {
  assert(typeof observation.responseBody === "string",
    "Storage observation lacks raw response bytes");
  const bytes = Buffer.from(observation.responseBody, "base64");
  assert.equal(bytes.toString("base64"), observation.responseBody,
    "Storage response bytes are not canonical base64");
  assert.equal(createHash("sha256").update(bytes).digest("hex"), hash,
    "Storage response hash differs from raw bytes");
  return bytes;
}

export function nativeStorageLoad(http, version) {
  const successful = http.filter(({ method, path, status }) =>
    method === "GET" && status >= 200 && status < 300
      && /\/git\/(commits|trees|blobs)\/([^/?]+)/.test(path));
  const selectedSummaryRequests = [...new Set(successful.flatMap(({ path }) => {
    const match = path.match(/\/git\/commits\/([^/?]+)/);
    return match ? [decodeURIComponent(match[1])] : [];
  }))];
  assert(selectedSummaryRequests.includes(version),
    "Native reader did not request the selected summary commit");
  const selectedTreeRequests = [...new Set(successful.flatMap(({ path }) => {
    const match = path.match(/\/git\/trees\/([^/?]+)/);
    return match ? [decodeURIComponent(match[1])] : [];
  }))];
  assert(selectedTreeRequests.length > 0,
    "Native reader did not request the selected summary trees");
  const selectedBlobRequests = [...new Set(successful.flatMap(({ path }) => {
    const match = path.match(/\/git\/blobs\/([^/?]+)/);
    return match ? [decodeURIComponent(match[1])] : [];
  }))];
  assert(selectedBlobRequests.length > 0,
    "Native reader did not request the selected summary blobs");
  const responseHashes = new Map();
  const storage = successful.flatMap((observation) => {
    const bytes = storageResponseBytes(observation, observation.responseHash);
    const identity = storageResponseIdentity(observation.path, bytes);
    if (observation.storageResponse !== undefined) {
      assert.deepEqual(identity, observation.storageResponse,
        "Storage identity differs from the request and raw response");
    }
    const [, kind, encodedId] = observation.path.match(
      /\/git\/(commits|trees|blobs)\/([^/?]+)/,
    );
    const requestedId = decodeURIComponent(encodedId);
    const key = `${kind}:${requestedId}`;
    if (responseHashes.has(key)) {
      assert.equal(observation.responseHash, responseHashes.get(key),
        "Storage returned conflicting responses to the same request");
    }
    responseHashes.set(key, observation.responseHash);
    const response = JSON.parse(bytes.toString("utf8"));
    if (response.sha !== undefined || response.id !== undefined) {
      assert.equal(response.sha ?? response.id, requestedId,
        "Storage response names another requested object");
    }
    return identity === undefined
      ? []
      : [{ ...identity, responseHash: observation.responseHash }];
  });
  const commit = storage.find(
    ({ kind, requestedId }) => kind === "commit" && requestedId === version,
  );
  assert(commit, "Native reader lacks the selected commit response identity");
  const trees = storage.filter(({ kind }) => kind === "tree");
  const root = trees.find(({ requestedId }) => requestedId === commit.treeId);
  assert(root, "Native reader lacks the selected root tree response identity");
  let protocolEntry = root.entries.find(
    ({ path, type }) => path === ".protocol" && type === "tree",
  );
  let app;
  if (protocolEntry === undefined) {
    const appEntry = root.entries.find(
      ({ path, type }) => path === ".app" && type === "tree",
    );
    assert(appEntry, "Native reader selected tree lacks .app or .protocol");
    app = trees.find(({ requestedId }) => requestedId === appEntry.id);
    assert(app, "Native reader lacks the selected .app tree response identity");
    protocolEntry = app.entries.find(
      ({ path, type }) => path === ".protocol" && type === "tree",
    );
  }
  assert(protocolEntry, "Native reader selected tree lacks .protocol");
  const protocol = trees.find(
    ({ requestedId }) => requestedId === protocolEntry.id,
  );
  assert(protocol, "Native reader lacks the selected protocol tree response identity");
  const attributes = protocol.entries.find(
    ({ path, type }) => path === "attributes" && type === "blob",
  );
  assert(attributes, "Native reader selected protocol tree lacks attributes");
  const blob = storage.find(
    ({ kind, requestedId }) =>
      kind === "blob" && requestedId === attributes.id,
  );
  assert(blob, "Native reader lacks the selected attributes blob response identity");
  assert(Number.isSafeInteger(blob.snapshotSequenceNumber)
    && blob.snapshotSequenceNumber >= 0,
  "Native reader attributes blob lacks a snapshot sequence");
  const snapshotSequenceNumber = blob.snapshotSequenceNumber;
  const storageResponses = {
    commit,
    trees: app === undefined ? [root, protocol] : [root, app, protocol],
    blob,
  };
  const rawLoadIdentity = {
    loadedVersion: version,
    commitId: commit.requestedId,
    rootTreeId: root.requestedId,
    protocolTreeId: protocol.requestedId,
    blobId: blob.requestedId,
    responseHash: blob.responseHash,
    snapshotSequenceNumber,
  };
  return {
    loadedVersion: version,
    selectedSummaryRequests,
    selectedTreeRequests,
    selectedBlobRequests,
    rawLoadIdentity,
    storageResponses,
    snapshotSequenceNumber,
  };
}

export function loadRequests(evidence, version) {
  const storage = nativeStorageLoad(evidence.http, version);
  const deliveredSequences = evidence.delivered
    .filter(({ direction, kind }) => direction === "inbound" && kind === "op")
    .flatMap(({ sequenceNumbers }) => sequenceNumbers)
    .filter(Number.isSafeInteger);
  const handshakeStarts = (evidence.handshakes ?? []).flatMap((handshake) => {
    const initial = handshake.initialMessageSequenceNumbers
      ?.filter(Number.isSafeInteger) ?? [];
    const applied = initial.filter((sequenceNumber) =>
      sequenceNumber > storage.snapshotSequenceNumber);
    if (applied.length > 0) return [Math.min(...applied) - 1];
    return [];
  });
  const deliveryStarts = deliveredSequences.length > 0
    ? [Math.min(...deliveredSequences) - 1]
    : [];
  const measuredStarts = deliveryStarts.length > 0 ? deliveryStarts : handshakeStarts;
  assert(measuredStarts.length > 0, "Native reader lacks measured replay evidence");
  return {
    ...storage,
    replayStartSequenceNumber: Math.min(...measuredStarts),
    replayEvidence: deliveryStarts.length > 0 ? "native-delivery" : "native-handshake",
  };
}

function restoredDetachedPoint(removed) {
  assert(Array.isArray(removed), "Fresh retained read has invalid removed content");
  const points = removed.flatMap((entry) => {
    if (!Array.isArray(entry) || entry.length !== 3) return [];
    const node = entry[2];
    if (!node || typeof node !== "object" || node.type !== Point.identifier) return [];
    const x = node.fields?.x?.[0]?.value;
    const y = node.fields?.y?.[0]?.value;
    return Number.isFinite(x) && Number.isFinite(y) ? [{ x, y }] : [];
  });
  const detached = points.find(({ x, y }) => x === 42 && y === 7);
  assert(detached, "Fresh retained read restored the wrong detached point");
  return detached;
}

export function storageLoad(observations, version) {
  for (const observation of observations) {
    if (observation.operation === "getVersions") {
      assert(Array.isArray(observation.request),
        "Upstream versions lack their request");
      const versions = JSON.parse(storageResponseBytes(observation, observation.hash));
      assert.deepEqual(versions.map(({ id, treeId }) => ({ id, treeId })),
        observation.versions, "Upstream versions differ from the raw response");
    }
    if (observation.operation === "getSnapshotTree") {
      const tree = JSON.parse(storageResponseBytes(observation, observation.hash));
      assert.deepEqual(tree, observation.tree,
        "Upstream snapshot differs from the raw response");
      assert.equal(tree.id, observation.id,
        "Upstream snapshot response names another tree");
    }
  }
  const selectedVersions = observations.flatMap((observation) =>
    observation.operation === "getVersions" ? observation.versions : []);
  const selectedSummaryRequests = [...new Set(selectedVersions.map(({ id }) => id))];
  assert(selectedSummaryRequests.includes(version),
    "Upstream reader did not select the published summary version");
  const selectedSummaryTreeId = selectedVersions.find(({ id }) => id === version)?.treeId;
  assert(typeof selectedSummaryTreeId === "string" && selectedSummaryTreeId.length > 0,
    "Selected summary version lacks its tree");
  const selectedTreeRequests = observations
    .filter(({ operation }) => operation === "getSnapshotTree")
    .flatMap(({ id }) => typeof id === "string" && id.length > 0 ? [id] : []);
  assert(selectedTreeRequests.includes(selectedSummaryTreeId),
    "Upstream reader did not request the selected snapshot");
  const selectedTreeResponse = observations.find(
    ({ operation, id }) =>
      operation === "getSnapshotTree" && id === selectedSummaryTreeId,
  );
  assert.equal(selectedTreeResponse?.request?.[0]?.id, version,
    "Upstream reader requested another snapshot version");
  assert.equal(selectedTreeResponse?.request?.[0]?.treeId, selectedSummaryTreeId,
    "Upstream reader requested another snapshot tree");
  const root = selectedTreeResponse?.tree;
  assert(root && root.id === selectedSummaryTreeId,
    "Upstream reader lacks the selected root tree response");
  const protocol = root.trees?.[".protocol"]
    ?? root.trees?.[".app"]?.trees?.[".protocol"];
  assert(typeof protocol?.id === "string" && protocol.id.length > 0,
    "Upstream reader selected tree lacks .protocol");
  const attributesBlobId = protocol.blobs?.attributes;
  assert(typeof attributesBlobId === "string" && attributesBlobId.length > 0,
    "Upstream reader selected protocol tree lacks attributes");
  const selectedBlobRequests = observations
    .filter(({ operation }) => operation === "readBlob")
    .map((observation) => {
      const { id, byteLength, hash } = observation;
      const bytes = storageResponseBytes(observation, hash);
      assert.equal(bytes.length, byteLength, "Upstream blob response length changed");
      const sequenceNumber = snapshotSequenceNumber(bytes);
      assert.equal(observation.snapshotSequenceNumber, sequenceNumber,
        "Upstream snapshot sequence differs from raw blob bytes");
      return {
        id,
        byteLength,
        hash,
        ...(sequenceNumber === undefined
          ? {}
          : { snapshotSequenceNumber: sequenceNumber }),
      };
    });
  assert(selectedBlobRequests.some(({ id, byteLength, hash }) =>
    typeof id === "string" && id.length > 0
      && Number.isSafeInteger(byteLength) && byteLength > 0
      && typeof hash === "string" && hash.length > 0),
    "Upstream reader did not read the selected summary hierarchy");
  const identities = selectedBlobRequests.filter(
    ({ id, snapshotSequenceNumber }) =>
      id === attributesBlobId
        &&
      Number.isSafeInteger(snapshotSequenceNumber)
        && snapshotSequenceNumber >= 0,
  );
  assert.equal(identities.length, 1,
    "Upstream reader lacks one consumed snapshot identity");
  const replayStarts = observations.flatMap(({ operation, from }) =>
    operation === "fetchMessages" && Number.isSafeInteger(from) ? [from] : []);
  assert(replayStarts.length > 0, "Upstream reader lacks measured delta replay");
  return {
    loadedVersion: version,
    selectedSummaryRequests,
    selectedSummaryTreeId,
    selectedTreeRequests,
    selectedBlobRequests,
    rawLoadIdentity: {
      loadedVersion: version,
      treeId: selectedSummaryTreeId,
      protocolTreeId: protocol.id,
      blobId: identities[0].id,
      blobHash: identities[0].hash,
      snapshotSequenceNumber: identities[0].snapshotSequenceNumber,
    },
    snapshotSequenceNumber: identities[0].snapshotSequenceNumber,
    replayStartSequenceNumber: Math.min(...replayStarts),
    replayEvidence: "upstream-delta-storage",
  };
}

function writerIdentity(history, adapters, writer) {
  const clientIds = adapters[writer].clientIds;
  const submissions = decodeTreeSubmissions(history)
    .filter(({ clientId }) => clientIds.has(clientId));
  assert(submissions.length > 0, `${writer} has no measured tree submissions`);
  const commits = submissions.flatMap(({ referenceSequenceNumber, commits }) =>
    commits.map((commit) => ({
      referenceSequenceNumber,
      revision: commit.revision,
      originatorId: commit.originatorId,
      refresher: refresherValues(commit),
    })));
  const originatorIds = [...new Set(commits.map(({ originatorId }) => originatorId))];
  assert.equal(originatorIds.length, 1,
    `${writer} changed compressor identity before publication`);
  return {
    clientIds: [...clientIds],
    originatorIds,
    resubmissions: commits.filter(({ refresher }) => refresher !== undefined),
  };
}

async function acknowledgedSubmission(session, adapter, afterSequence, label) {
  const history = await serverHistory(session);
  const submission = decodeTreeSubmissions(history).find(
    ({ outerSequenceNumber, clientId }) =>
      outerSequenceNumber > afterSequence && adapter.clientIds.has(clientId),
  );
  assert(submission, `${label} acknowledged submission is missing from history`);
  return submission;
}

function continuationIdentity(history, adapter, sequenceNumber) {
  const submission = decodeTreeSubmissions(history).find(({ outerSequenceNumber, clientId }) =>
    outerSequenceNumber === sequenceNumber && adapter.clientIds.has(clientId));
  assert(submission, "Reader continuation lacks compressor identity");
  return {
    clientId: submission.clientId,
    referenceSequenceNumber: submission.referenceSequenceNumber,
    revisions: submission.commits.map(({ revision, originatorId }) => ({
      revision,
      originatorId,
    })),
  };
}

async function publishWriterSummary(
  config,
  containers,
  creator,
  documentId,
  jwt,
  writer,
  adapters,
  {
    store,
    tailEdit = (adapter, value) => adapter.set(["note"], value),
  } = {},
) {
  const tailAuthor = writer === "javascript" ? "erlang" : "javascript";
  const tailBaseline = await adapters[tailAuthor].checkpoint();
  let version;
  let snapshotSequenceNumber;
  let dataEdit;
  if (writer === "upstream") {
    const summarizer = await openSession(
      config,
      containers,
      documentId,
      true,
      store ? { store } : undefined,
    );
    assert(summarizer.data.ISummarizer, "Missing upstream summarizer");
    await summarizer.container.deltaManager.outbound.pause();
    const result = summarizer.data.ISummarizer.summarizeOnDemand({
      reason: "Task 4 selected upstream writer",
      fullTree: true,
    });
    const submitted = await result.summarySubmitted;
    assert(submitted.success, `Summary submission failed: ${submitted.error}`);
    snapshotSequenceNumber = submitted.data.referenceSequenceNumber;
    assert(summarizer.container.deltaManager.outbound.length > 0,
      "Upstream summarize operation was not held after upload");
    await tailEdit(adapters[tailAuthor], `between-${writer}-${randomUUID()}`);
    await adapters[tailAuthor].awaitSynced();
    dataEdit = await acknowledgedSubmission(
      creator,
      adapters[tailAuthor],
      tailBaseline.sequenceNumber,
      tailAuthor,
    );
    summarizer.container.deltaManager.outbound.resume();
    const broadcast = await result.summaryOpBroadcasted;
    assert(broadcast.success, `Summary broadcast failed: ${broadcast.error}`);
    const acknowledged = await result.receivedSummaryAckOrNack;
    assert(acknowledged.success, `Summary acknowledgement failed: ${acknowledged.error}`);
    version = acknowledged.data.summaryAckOp.contents.handle;
    summarizer.container.dispose();
  } else {
    const adapter = adapters[writer];
    const before = adapter.evidence().http.length;
    adapter.client.gate.hold("outbound", "summarize");
    const published = adapter.summarize().then(
      (value) => ({ value }),
      (error) => ({ error }),
    );
    try {
      await until(() => {
        const evidence = adapter.evidence();
        return evidence.held.some(({ direction, kind }) =>
          direction === "outbound" && kind === "summarize")
          && evidence.http.slice(before).some(({ method, path, status }) =>
            method === "POST" && path.includes("/git/trees")
              && status >= 200 && status < 300);
      }, `${writer} summary capture and upload`);
    } catch (error) {
      const evidence = adapter.evidence();
      try {
        await adapter.client.gate.release("outbound");
      } catch {
        // The native summary timeout can close the socket before diagnostics run.
      }
      throw new Error(`${error.message}: ${JSON.stringify(evidence)}`, { cause: error });
    }
    await tailEdit(adapters[tailAuthor], `between-${writer}-${randomUUID()}`);
    await adapters[tailAuthor].awaitSynced();
    await adapter.client.gate.release("outbound");
    const outcome = await published;
    if (outcome.error) {
      throw new Error(`${writer} publication failed after release: `
        + `${JSON.stringify(adapter.evidence())}`, { cause: outcome.error });
    }
    version = outcome.value;
    dataEdit = await acknowledgedSubmission(
      creator,
      adapters[tailAuthor],
      tailBaseline.sequenceNumber,
      tailAuthor,
    );
    snapshotSequenceNumber = await publishedSequence(config, documentId, jwt, version);
  }
  assert.equal(await publishedSequence(config, documentId, jwt, version),
    snapshotSequenceNumber, "Submitted and stored summary positions differ");
  const publicationSequenceNumber = await publicationSequence(
    config,
    documentId,
    jwt,
    version,
    snapshotSequenceNumber,
  );
  assert(snapshotSequenceNumber < dataEdit.outerSequenceNumber
    && dataEdit.outerSequenceNumber < publicationSequenceNumber,
  "Selected summary lacks an actual data operation before publication");
  assert.equal(await publishedVersion(config, documentId, jwt), version,
    "Published summary is not the document head");
  return {
    version,
    snapshotSequenceNumber,
    dataEditSequenceNumber: dataEdit.outerSequenceNumber,
    publicationSequenceNumber,
  };
}

async function publishPendingSchemaSummary(
  config,
  containers,
  documentId,
  jwt,
  writer,
  adapters,
  context,
) {
  let publisher;
  try {
    const version = writer === "upstream"
      ? (await publishUpstreamSummary(
        config,
        containers,
        documentId,
        `Task 10 ${writer} pending schema capture`,
        { store: schemaEvolutionServiceStore },
      )).summaryAckOp.contents.handle
      : await (async () => {
        publisher = await nativeAdapter(writer, config, {
          runId: context.runId,
          documentId,
          tenant: config.tenantId,
          viewSchema: context.schemaViews.v1,
          viewSchemas: context.schemaViews,
        }, jwt);
        await publisher.awaitSynced();
        return publisher.summarize();
      })();
    const snapshotSequenceNumber = await publishedSequence(
      config,
      documentId,
      jwt,
      version,
    );
    return {
      version,
      snapshotSequenceNumber,
      publicationSequenceNumber: await publicationSequence(
        config,
        documentId,
        jwt,
        version,
        snapshotSequenceNumber,
      ),
    };
  } finally {
    await publisher?.close();
  }
}

async function verifyPendingSchemaPublication(
  config,
  containers,
  documentId,
  version,
  snapshotSequenceNumber,
) {
  const session = await openSession(
    config,
    containers,
    documentId,
    false,
    {
      cache: false,
      observeStorage: true,
      store: schemaEvolutionServiceStore,
    },
  );
  const adapter = upstreamAdapter(session, schemaEvolutionConfigurations);
  await adapter.awaitSynced(snapshotSequenceNumber);
  const checkpoint = await adapter.checkpoint();
  const load = storageLoad(session.storageObservations, version);
  session.container.dispose();
  return { checkpoint, load };
}

export async function readCell(config, context, row, reader, {
  getPublishedVersion = publishedVersion,
  makeNativeAdapter = nativeAdapter,
  openUpstreamSession = openSession,
  makeUpstreamAdapter = upstreamAdapter,
} = {}) {
  const containers = [];
  let adapter;
  let readError;
  try {
    const headBefore = await getPublishedVersion(
      config,
      row.documentId,
      row.jwt,
    );
    assert.equal(headBefore, row.version, "Writer head changed before reload");
    let load;
    let rawLoad;
    let loaded;
    if (reader === "upstream") {
      const session = await openUpstreamSession(config, containers, row.documentId, false, {
        cache: false,
        observeStorage: true,
      });
      adapter = makeUpstreamAdapter(session);
      await adapter.awaitSynced(row.publicationSequenceNumber);
      load = storageLoad(session.storageObservations, row.version);
      rawLoad = session.storageObservations;
    } else {
      adapter = await makeNativeAdapter(reader, config, {
        runId: context.runId,
        documentId: row.documentId,
        tenant: config.tenantId,
        viewSchema: context.viewSchema,
      }, row.jwt);
      await adapter.awaitSynced(row.publicationSequenceNumber);
      loaded = await adapter.checkpoint();
      rawLoad = adapter.evidence();
      load = loadRequests(rawLoad, row.version, row.snapshotSequenceNumber);
    }
    assert(load.replayStartSequenceNumber >= row.snapshotSequenceNumber,
      `Fresh reader replayed from before the selected summary: ${JSON.stringify({
        reader,
        snapshotSequenceNumber: row.snapshotSequenceNumber,
        load,
        handshakes: rawLoad?.handshakes,
      })}`);
    loaded ??= await adapter.checkpoint();
    assert.deepEqual(loaded.wholeTree,
      canonicalValue(rootValue(row.observer.data.view.root)),
    `${reader} loaded a different typed root`);
    const continuationTitle = `${row.writer}-${reader}-${randomUUID()}`;
    const baseline = loaded.sequenceNumber;
    await adapter.set(["title"], continuationTitle);
    await adapter.awaitSynced();
    await until(() => row.observer.data.view.root.title === continuationTitle,
      `${reader} continuation observation`);
    const continuation = await acknowledgedSubmission(
      row.observer,
      adapter,
      baseline,
      reader,
    );
    const final = await adapter.checkpoint();
    const history = await serverHistory(row.observer);
    const headAfter = await getPublishedVersion(config, row.documentId, row.jwt);
    assert.equal(headAfter, row.version, "Reader unexpectedly changed the writer head");
    const item = {
      runId: context.runId,
      profileDigest: context.profileDigest,
      writer: row.writer,
      reader,
      writerVersion: row.version,
      loadedVersion: load.loadedVersion,
      readerInstanceId: adapter.instanceId,
      snapshotSequenceNumber: row.snapshotSequenceNumber,
      dataEditSequenceNumber: row.dataEditSequenceNumber,
      publicationSequenceNumber: row.publicationSequenceNumber,
      replayWatermark: final.sequenceNumber,
      replayStartSequenceNumber: load.replayStartSequenceNumber,
      replayEvidence: load.replayEvidence,
      selectedSummaryRequests: load.selectedSummaryRequests,
      scenarioId: "summary-tail-retained-bootstrap",
      loaded: true,
      continuedEditing: true,
      peerObservedEdit: true,
      pendingTreeCount: final.pendingTreeCount,
      inflightSubmissionCount: final.inflightSubmissionCount,
      wholeTree: final.wholeTree,
      documentId: row.documentId,
      writerVersionBeforeLoad: headBefore,
      writerVersionAfterLoad: headAfter,
      tailSequenceNumber: row.tailSequenceNumber,
      retained: row.retained,
      continuationIdentity: continuationIdentity(
        history,
        adapter,
        continuation.outerSequenceNumber,
      ),
      artifacts: [],
    };
    item.artifacts = [await writeReloadArtifact(context, item, {
      load: rawLoad,
      history,
      retainedLoad: row.retainedLoad,
    })];
    return item;
  } catch (error) {
    readError = error;
    throw error;
  } finally {
    const cleanup = [];
    if (reader === "upstream") {
      for (const container of containers.toReversed()) {
        if (!container.closed) cleanup.push(() => container.dispose());
      }
    } else if (adapter) {
      cleanup.push(() => adapter.close());
    }
    await cleanupAll(readError, `${reader} reload reader cleanup failed`, cleanup);
  }
}

async function runWriterRow(config, context, writer) {
  const containers = [];
  const natives = [];
  let rowError;
  try {
    const creator = await openSession(config, containers);
    const documentId = creator.container.resolvedUrl.id;
    creator.data.view.root.point = { x: 1, y: 2 };
    creator.data.bootstrap.set("historyFence", `bootstrap-${writer}`);
    await until(() => !creator.container.isDirty, `${writer} row bootstrap`);
    await publishUpstreamSummary(
      config,
      containers,
      documentId,
      `Task 4 ${writer} bootstrap`,
    );
    const bootstrapSummarizer = containers.at(-1);
    if (bootstrapSummarizer !== creator.container) bootstrapSummarizer.dispose();
    const upstream = upstreamAdapter(await openSession(config, containers, documentId));
    const { jwt } = await tokenProvider(config).fetchOrdererToken(
      config.tenantId,
      documentId,
    );
    for (const target of nativeTargets) {
      natives.push(await nativeAdapter(target, config, {
        runId: context.runId,
        documentId,
        tenant: config.tenantId,
        viewSchema: context.viewSchema,
      }, jwt));
    }
    const adapters = {
      upstream,
      javascript: natives[0],
      erlang: natives[1],
    };
    await settle(adapters);
    await adapters.upstream.set(["title"], `${writer}-upstream`);
    await adapters.upstream.awaitSynced();
    await adapters.javascript.set(["enabled"], true);
    await adapters.javascript.awaitSynced();
    await adapters.erlang.set(["rating"], implementations.indexOf(writer) + 1);
    await adapters.erlang.awaitSynced();
    await settle(adapters);

    const oldPoint = upstream.session.data.view.root.point;
    if (writer === "upstream") {
      await adapters.upstream.holdInbound();
      await adapters.upstream.holdOutbound();
      oldPoint.x = 42;
      oldPoint.y = 7;
      await until(async () => {
        const checkpoint = await adapters.upstream.checkpoint();
        return checkpoint.pendingTreeCount + checkpoint.inflightSubmissionCount >= 2;
      }, "upstream retained child edits");
      await adapters.javascript.set(["point"], { x: 3, y: 4 });
      await adapters.javascript.awaitSynced();
      await adapters.upstream.releaseOutbound();
      await adapters.upstream.releaseInbound();
    } else {
      await adapters[writer].holdInbound();
      await adapters[writer].holdOutbound();
      await adapters[writer].set(["point", "x"], 42);
      await adapters[writer].set(["point", "y"], 7);
      const pending = await adapters[writer].checkpoint();
      assert.equal(pending.pendingTreeCount, 2,
        `${writer} retained scenario lacks two pending child edits`);
      await adapters.upstream.set(["point"], { x: 3, y: 4 });
      await adapters.upstream.awaitSynced();
      await adapters[writer].reconnect();
    }
    await settle(adapters);
    assert.deepEqual({ x: oldPoint.x, y: oldPoint.y }, { x: 42, y: 7 },
      `${writer} detached point lost retained edits`);
    assert.deepEqual({
      x: upstream.session.data.view.root.point.x,
      y: upstream.session.data.view.root.point.y,
    }, { x: 3, y: 4 }, `${writer} visible point changed to detached content`);

    const beforePublication = await serverHistory(creator);
    const retainedIdentity = writerIdentity(beforePublication, adapters, writer);
    if (writer !== "upstream") {
      assert.deepEqual(
        retainedIdentity.resubmissions.map(({ refresher }) => refresher),
        [[1, 2], [42, 2]],
        `${writer} retained resubmission metadata changed`,
      );
    }
    const publication = await publishWriterSummary(
      config,
      containers,
      creator,
      documentId,
      jwt,
      writer,
      adapters,
      context,
    );

    for (const native of natives.toReversed()) await native.close();
    natives.length = 0;
    if (!upstream.session.container.closed) upstream.session.container.dispose();

    creator.data.bootstrap.set("historyFence", `after-${writer}-${randomUUID()}`);
    await until(() => !creator.container.isDirty, `${writer} non-tree tail`);
    const tailHistory = await serverHistory(creator);
    const tail = tailHistory.findLast(({ clientId, sequenceNumber, type }) =>
      clientId === creator.container.clientId
        && sequenceNumber > publication.publicationSequenceNumber
        && type === "op");
    assert(tail, `${writer} lacks a non-tree tail after publication`);

    const verifier = await openSession(config, containers, documentId, false, {
      cache: false,
      observeStorage: true,
    });
    const retainedLoad = storageLoad(verifier.storageObservations, publication.version);
    assert(retainedLoad.replayStartSequenceNumber >= publication.snapshotSequenceNumber,
      "Retained verifier replayed from the document origin");
    assert.deepEqual({
      x: verifier.data.view.root.point.x,
      y: verifier.data.view.root.point.y,
    }, { x: 3, y: 4 }, "Fresh retained read changed the visible point");
    assert.equal(verifier.data.bootstrap.get("historyFence"),
      creator.data.bootstrap.get("historyFence"),
    "Fresh retained read missed the bootstrap-map tail");
    const removed = verifier.data.tree.contentSnapshot().removed;
    assert(removed.length > 0, "Fresh retained read omitted detached content");
    const detached = restoredDetachedPoint(removed);
    const retained = {
      visible: { x: 3, y: 4 },
      detached,
      removed,
      writerIdentity: retainedIdentity,
      upstreamSelectedVersion: retainedLoad.loadedVersion,
      summaryConsumed: true,
    };
    verifier.container.dispose();

    const row = {
      writer,
      documentId,
      jwt,
      observer: creator,
      retained,
      retainedLoad: verifier.storageObservations,
      tailSequenceNumber: tail.sequenceNumber,
      ...publication,
    };
    const results = {};
    for (const reader of implementations) {
      results[reader] = await readCell(config, context, row, reader);
    }
    return results;
  } catch (error) {
    rowError = error;
    throw error;
  } finally {
    const cleanupErrors = [];
    for (const native of natives.toReversed()) {
      try {
        await native.close();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    for (const container of containers.toReversed()) {
      try {
        if (!container.closed) container.dispose();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    if (cleanupErrors.length > 0) {
      if (rowError) rowError.cleanupErrors = cleanupErrors;
      else throw new AggregateError(cleanupErrors, `Cleanup failed for ${writer} reload row`);
    }
  }
}

export async function runReloadMatrix(config, context) {
  assert(typeof context?.runId === "string" && context.runId.length > 0,
    "runReloadMatrix context requires runId");
  assert(typeof context.profileDigest === "string"
    && /^[0-9a-f]{64}$/.test(context.profileDigest),
  "runReloadMatrix context requires profileDigest");
  assert(typeof context.viewSchema === "string" && context.viewSchema.length > 0,
    "runReloadMatrix context requires viewSchema");
  assert(typeof context.artifactDirectory === "string"
    && context.artifactDirectory.length > 0,
  "runReloadMatrix context requires artifactDirectory");
  const results = {};
  for (const writer of implementations) {
    results[writer] = await runWriterRow(config, context, writer);
  }
  return validateResults(results);
}

const mapPointValue = (x, y) => ({
  kind: "object",
  schemaId: "org.watershed.shared-tree.m2.Point",
  fields: [
    ["x", { kind: "number", value: x }],
    ["y", { kind: "number", value: y }],
  ],
});

const dynamicMapValue = (entries) => ({
  kind: "map",
  schemaId: "org.watershed.shared-tree.m2.DynamicMap",
  entries,
});

async function readMapCell(config, context, row, reader) {
  const containers = [];
  let adapter;
  let readError;
  try {
    const headBefore = await publishedVersion(config, row.documentId, row.jwt);
    assert.equal(headBefore, row.version, "Map writer head changed before reload");
    let load;
    let rawLoad;
    let loaded;
    if (reader === "upstream") {
      const session = await openSession(
        config,
        containers,
        row.documentId,
        false,
        { cache: false, observeStorage: true, store: mapServiceStore },
      );
      adapter = upstreamAdapter(session);
      await adapter.awaitSynced(row.publicationSequenceNumber);
      load = storageLoad(session.storageObservations, row.version);
      rawLoad = session.storageObservations;
    } else {
      adapter = await nativeAdapter(reader, config, {
        runId: context.runId,
        documentId: row.documentId,
        tenant: config.tenantId,
        viewSchema: context.mapViewSchema,
      }, row.jwt);
      await adapter.awaitSynced(row.publicationSequenceNumber);
      loaded = await adapter.checkpoint();
      rawLoad = adapter.evidence();
      load = loadRequests(rawLoad, row.version, row.snapshotSequenceNumber);
    }
    assert(load.replayStartSequenceNumber >= row.snapshotSequenceNumber,
      "Fresh map reader replayed from before the selected summary");
    loaded ??= await adapter.checkpoint();
    const expected = await row.observerAdapter.checkpoint();
    assert.deepEqual(loaded.wholeTree, expected.wholeTree,
      `${reader} loaded a different map root`);
    assert.equal((await adapter.mapGet(["items"], "deleted")).present, false,
      `${reader} restored the deleted map entry`);
    assert.deepEqual(await adapter.mapGet(["items"], "tail"), {
      present: true,
      value: row.tailValue,
    }, `${reader} missed the post-summary map tail`);

    const continuationKey = `reader-${writerReaderKey(row.writer, reader)}`;
    const continuationValue = {
      kind: "string",
      value: `${row.writer}-${reader}-${randomUUID()}`,
    };
    const baseline = loaded.sequenceNumber;
    await adapter.mapSet(["items"], continuationKey, continuationValue);
    await adapter.awaitSynced();
    await until(() => mapEntryMatches(
      row.observer.data.view.root,
      continuationKey,
      continuationValue,
    ),
      `${reader} map continuation observation`);
    const continuation = await acknowledgedSubmission(
      row.observer,
      adapter,
      baseline,
      reader,
    );
    const final = await adapter.checkpoint();
    const history = await serverHistory(row.observer);
    const headAfter = await publishedVersion(config, row.documentId, row.jwt);
    assert.equal(headAfter, row.version, "Map reader unexpectedly changed the writer head");
    const item = {
      runId: context.runId,
      profileDigest: context.profileDigest,
      profile: "map",
      writer: row.writer,
      reader,
      writerVersion: row.version,
      loadedVersion: load.loadedVersion,
      readerInstanceId: adapter.instanceId,
      snapshotSequenceNumber: row.snapshotSequenceNumber,
      dataEditSequenceNumber: row.dataEditSequenceNumber,
      publicationSequenceNumber: row.publicationSequenceNumber,
      replayWatermark: final.sequenceNumber,
      replayStartSequenceNumber: load.replayStartSequenceNumber,
      replayEvidence: load.replayEvidence,
      selectedSummaryRequests: load.selectedSummaryRequests,
      scenarioId: "map-summary-tail-retained",
      loaded: true,
      tailObserved: true,
      continuedEditing: true,
      peerObservedEdit: true,
      deletedEntryAbsent: true,
      pendingTreeCount: final.pendingTreeCount,
      inflightSubmissionCount: final.inflightSubmissionCount,
      wholeTree: final.wholeTree,
      documentId: row.documentId,
      writerVersionBeforeLoad: headBefore,
      writerVersionAfterLoad: headAfter,
      tailSequenceNumber: row.tailSequenceNumber,
      retained: row.retained,
      continuationIdentity: continuationIdentity(
        history,
        adapter,
        continuation.outerSequenceNumber,
      ),
      artifacts: [],
    };
    item.artifacts = [await writeMapReloadArtifact(context, item, {
      load: rawLoad,
      history,
      retainedLoad: row.retainedLoad,
    })];
    return item;
  } catch (error) {
    readError = error;
    throw error;
  } finally {
    const cleanup = [];
    if (reader === "upstream") {
      for (const container of containers.toReversed()) {
        if (!container.closed) cleanup.push(() => container.dispose());
      }
    } else if (adapter) {
      cleanup.push(() => adapter.close());
    }
    await cleanupAll(readError, `${reader} map reload reader cleanup failed`, cleanup);
  }
}

function writerReaderKey(writer, reader) {
  return `${writer}-${reader}`;
}

export function mapEntryMatches(root, key, expected) {
  if (!root.items.has(key)) return false;
  const actual = root.items.get(key);
  if (expected.kind === "null") return actual === null;
  if (["string", "number", "boolean"].includes(expected.kind)) {
    return actual === expected.value;
  }
  return false;
}

const arrayPointValue = (label, x) => ({
  kind: "object",
  schemaId: "org.watershed.shared-tree.m3.Point",
  fields: [
    ["label", { kind: "string", value: label }],
    ["x", { kind: "number", value: x }],
  ],
});

const identifierPointValue = (label, id) => ({
  kind: "object",
  schemaId: "org.watershed.shared-tree.identifiers.Point",
  fields: [
    ...(id === undefined ? [] : [["id", { kind: "string", value: id }]]),
    ["label", { kind: "string", value: label }],
  ],
});

function identifierNodes(checkpoint) {
  const fields = Object.fromEntries(checkpoint.wholeTree.value.fields);
  return ["left", "right"].flatMap((name) => fields[name].elements)
    .map((node) => Object.fromEntries(node.fields.map(([key, value]) =>
      [key, value.value])));
}

function identifierByLabel(checkpoint, label) {
  const node = identifierNodes(checkpoint).find((item) => item.label === label);
  assert(node, `Identifier checkpoint lacks ${label}`);
  return node;
}

async function writeIdentifierReloadArtifact(context, item, raw) {
  const relative = `identifier-reload/${item.writer}-${item.reader}.json`;
  const path = join(context.artifactDirectory, relative);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify({
    formatVersion: 1,
    runId: context.runId,
    profileDigest: context.profileDigest,
    kind: "identifier-reload",
    subject: `${item.writer}->${item.reader}`,
    documentId: item.documentId,
    measured: {
      writerAuthored: item.writerAuthored,
      postLoadAuthored: item.postLoadAuthored,
      peerObservation: item.peerObservation,
    },
    raw,
  })}\n`, { mode: 0o600 });
  return relative;
}

async function readIdentifierCell(config, context, row, reader) {
  const containers = [];
  let adapter;
  let failure;
  try {
    let load;
    let rawLoad;
    let loaded;
    if (reader === "upstream") {
      const session = await openSession(
        config,
        containers,
        row.documentId,
        false,
        { cache: false, observeStorage: true, store: identifierServiceStore },
      );
      adapter = upstreamAdapter(session);
      await adapter.awaitSynced(row.publicationSequenceNumber);
      load = storageLoad(session.storageObservations, row.version);
      rawLoad = session.storageObservations;
    } else {
      adapter = await nativeAdapter(reader, config, {
        runId: context.runId,
        documentId: row.documentId,
        tenant: config.tenantId,
        viewSchema: context.identifierViewSchema,
      }, row.jwt);
      await adapter.awaitSynced(row.publicationSequenceNumber);
      loaded = await adapter.checkpoint();
      rawLoad = adapter.evidence();
      load = loadRequests(rawLoad, row.version, row.snapshotSequenceNumber);
    }
    loaded ??= await adapter.checkpoint();
    assert.equal(identifierByLabel(loaded, `${row.writer}-default`).id,
      row.writerAuthored.defaultId, "Identifier reload changed the generated ID");
    assert.equal(identifierByLabel(loaded, `${row.writer}-explicit`).id,
      row.writerAuthored.explicitId, "Identifier reload changed the explicit ID");
    const label = `${row.writer}-${reader}-postload`;
    const baseline = loaded.sequenceNumber;
    await adapter.arrayInsert(["left"], 1, [identifierPointValue(label)]);
    await adapter.awaitSynced();
    const continuation = await acknowledgedSubmission(
      row.observer,
      adapter,
      baseline,
      reader,
    );
    const authored = await adapter.checkpoint();
    const identifier = identifierByLabel(authored, label).id;
    const peer = await openSession(
      config,
      containers,
      row.documentId,
      false,
      { cache: false, store: identifierServiceStore },
    );
    const peerAdapter = upstreamAdapter(peer);
    await peerAdapter.awaitSynced(continuation.outerSequenceNumber);
    const peerCheckpoint = await peerAdapter.checkpoint();
    assert.equal(identifierByLabel(peerCheckpoint, label).id, identifier,
      "Identifier post-load edit differs on the peer");
    const commit = continuation.commits[0];
    const range = continuation.allocations[0];
    assert(commit && range, "Identifier post-load edit lacks operation identity");
    const item = {
      runId: context.runId,
      profileDigest: context.profileDigest,
      profile: "identifier",
      writer: row.writer,
      reader,
      writerVersion: row.version,
      loadedVersion: load.loadedVersion,
      readerInstanceId: adapter.instanceId,
      scenarioId: "identifier-summary-postload",
      loaded: true,
      writerAuthored: row.writerAuthored,
      postLoadAuthored: {
        author: reader,
        id: identifier,
        originatorId: commit.originatorId,
        allocationRange: {
          sessionId: range.sessionId,
          ids: {
            first: range.first,
            count: range.last - range.first + 1,
          },
        },
      },
      peerObservation: {
        implementation: "upstream",
        id: identifier,
        observed: true,
      },
      pendingTreeCount: authored.pendingTreeCount,
      inflightSubmissionCount: authored.inflightSubmissionCount,
      documentId: row.documentId,
      artifacts: [],
    };
    item.artifacts = [await writeIdentifierReloadArtifact(context, item, {
      load: rawLoad,
      continuation,
      peer: peerCheckpoint,
      history: await serverHistory(row.observer),
    })];
    return item;
  } catch (error) {
    failure = error;
    throw error;
  } finally {
    const cleanup = [];
    if (adapter && reader !== "upstream") cleanup.push(() => adapter.close());
    for (const container of containers.toReversed()) {
      if (!container.closed) cleanup.push(() => container.dispose());
    }
    await cleanupAll(failure, `${reader} Identifier reload cleanup failed`, cleanup);
  }
}

async function runIdentifierWriterRow(config, context, writer) {
  const containers = [];
  const natives = [];
  let failure;
  try {
    const creator = await openSession(
      config,
      containers,
      undefined,
      false,
      { store: identifierServiceStore },
    );
    const documentId = creator.container.resolvedUrl.id;
    await publishUpstreamSummary(
      config,
      containers,
      documentId,
      `Identifier ${writer} bootstrap`,
      { store: identifierServiceStore },
    );
    const upstreamSession = await openSession(
      config,
      containers,
      documentId,
      false,
      { store: identifierServiceStore },
    );
    const upstream = upstreamAdapter(upstreamSession);
    const { jwt } = await tokenProvider(config).fetchOrdererToken(
      config.tenantId,
      documentId,
    );
    for (const target of nativeTargets) {
      natives.push(await nativeAdapter(target, config, {
        runId: context.runId,
        documentId,
        tenant: config.tenantId,
        viewSchema: context.identifierViewSchema,
      }, jwt));
    }
    const adapters = {
      upstream,
      javascript: natives[0],
      erlang: natives[1],
    };
    await settle(adapters);
    await adapters[writer].arrayInsert(["left"], 0, [
      identifierPointValue(`${writer}-default`),
    ]);
    await adapters[writer].arrayInsert(["right"], 0, [
      identifierPointValue(`${writer}-explicit`, "shared-custom-id"),
    ]);
    await settle(adapters);
    const writerCheckpoint = await adapters[writer].checkpoint();
    const publication = await publishWriterSummary(
      config,
      containers,
      creator,
      documentId,
      jwt,
      writer,
      adapters,
      {
        store: identifierServiceStore,
        tailEdit: (adapter, label) =>
          adapter.arrayInsert(["right"], 1, [identifierPointValue(label)]),
      },
    );
    const row = {
      writer,
      documentId,
      jwt,
      observer: creator,
      writerAuthored: {
        defaultId: identifierByLabel(writerCheckpoint, `${writer}-default`).id,
        explicitId: identifierByLabel(writerCheckpoint, `${writer}-explicit`).id,
      },
      ...publication,
    };
    for (const native of natives.toReversed()) await native.close();
    natives.length = 0;
    if (!upstream.session.container.closed) upstream.session.container.dispose();
    const results = {};
    for (const reader of implementations) {
      results[reader] = await readIdentifierCell(config, context, row, reader);
    }
    return results;
  } catch (error) {
    failure = error;
    throw error;
  } finally {
    const cleanupErrors = [];
    for (const native of natives.toReversed()) {
      try {
        await native.close();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    for (const container of containers.toReversed()) {
      try {
        if (!container.closed) container.dispose();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    if (cleanupErrors.length > 0) {
      if (failure) {
        failure.cleanupErrors = [
          ...(failure.cleanupErrors ?? []),
          ...cleanupErrors,
        ];
      }
      else throw new AggregateError(
        cleanupErrors,
        `Cleanup failed for ${writer} Identifier reload row`,
      );
    }
  }
}

const arrayItemsValue = (elements) => ({
  kind: "array",
  schemaId: "org.watershed.shared-tree.m3.Items",
  elements,
});

const arrayMapValue = (entries) => ({
  kind: "map",
  schemaId: "org.watershed.shared-tree.m3.ArrayMap",
  entries,
});

function expectedArrayTree(writer, continuationLabel = undefined) {
  const moved = continuationLabel === undefined
    ? arrayPointValue("moved", 4)
    : arrayPointValue(continuationLabel, 42);
  return {
    present: true,
    value: {
      kind: "object",
      schemaId: "org.watershed.shared-tree.m3.Root",
      fields: [
        ["byKey", arrayMapValue([
          ["", arrayItemsValue([])],
          ["0", arrayItemsValue([arrayPointValue("numeric", 0)])],
        ])],
        ["left", arrayItemsValue([
          ...(continuationLabel === undefined ? [] : [moved]),
          arrayPointValue("duplicate", 1),
          arrayPointValue("duplicate", 1),
          arrayItemsValue([arrayPointValue("nested", 2)]),
        ])],
        ["narrow", {
          kind: "array",
          schemaId: "org.watershed.shared-tree.m3.Points",
          elements: [],
        }],
        ["right", arrayItemsValue([
          arrayMapValue([["inside", arrayPointValue("map-child", 3)]]),
          ...(continuationLabel === undefined ? [moved] : []),
          arrayPointValue(`after-summary-${writer}`, 7),
        ])],
      ],
    },
  };
}

export async function continueArrayReader(adapter, label) {
  await adapter.arrayMove(["right"], 1, 2, ["left"], 0);
  await adapter.set(["left", "0", "label"], label);
  await adapter.set(["left", "0", "x"], 42);
}

export async function restoreArrayReader(adapter) {
  await adapter.set(["left", "0", "label"], "moved");
  await adapter.set(["left", "0", "x"], 4);
  await adapter.arrayMove(["left"], 0, 1, ["right"], 1);
}

async function readArrayCell(config, context, row, reader) {
  const containers = [];
  let adapter;
  let readError;
  try {
    const headBefore = await publishedVersion(config, row.documentId, row.jwt);
    assert.equal(headBefore, row.version, "Array writer head changed before reload");
    let load;
    let rawLoad;
    let loaded;
    if (reader === "upstream") {
      const session = await openSession(
        config,
        containers,
        row.documentId,
        false,
        { cache: false, observeStorage: true, store: arrayServiceStore },
      );
      adapter = upstreamAdapter(session);
      await adapter.awaitSynced(row.publicationSequenceNumber);
      load = storageLoad(session.storageObservations, row.version);
      rawLoad = session.storageObservations;
    } else {
      adapter = await nativeAdapter(reader, config, {
        runId: context.runId,
        documentId: row.documentId,
        tenant: config.tenantId,
        viewSchema: context.arrayViewSchema,
      }, row.jwt);
      await adapter.awaitSynced(row.publicationSequenceNumber);
      loaded = await adapter.checkpoint();
      rawLoad = adapter.evidence();
      load = loadRequests(rawLoad, row.version, row.snapshotSequenceNumber);
    }
    assert(load.replayStartSequenceNumber >= row.snapshotSequenceNumber,
      "Fresh array reader replayed from before the selected summary");
    loaded ??= await adapter.checkpoint();
    const expected = await row.observerAdapter.checkpoint();
    assert.deepEqual(loaded.wholeTree, expected.wholeTree,
      `${reader} loaded a different array root`);
    assert((await adapter.arrayValues(["right"]))
      .some((value) => JSON.stringify(value) === JSON.stringify(row.tailValue)),
    `${reader} missed the post-summary array tail`);

    const retained = loaded.retained;
    assert(retained && Array.isArray(retained.removed),
      `${reader} array checkpoint lacks reader-owned removed content`);
    const removed = retained.removed;
    assert(removed.length > 0, `${reader} array checkpoint omitted deleted content`);
    const retainedHistory = reader === "upstream"
      ? row.selectedMoveHistory
      : retained.history;
    const persistedMoveIdentity = retainedMoveIdentity(retainedHistory);
    const peer = await openSession(
      config,
      containers,
      row.documentId,
      false,
      { cache: false, store: arrayServiceStore },
    );

    const continuationLabel = `${row.writer}-${reader}-${randomUUID()}`;
    const baseline = loaded.sequenceNumber;
    await continueArrayReader(adapter, continuationLabel);
    await adapter.awaitSynced();
    const continuation = await acknowledgedSubmission(
      row.observer,
      adapter,
      baseline,
      reader,
    );
    const continuationCheckpoint = await adapter.checkpoint();
    const peerAdapter = upstreamAdapter(peer);
    await peerAdapter.awaitSynced(continuation.outerSequenceNumber);
    const peerCheckpoint = await peerAdapter.checkpoint();
    assert.deepEqual(peerCheckpoint.wholeTree, continuationCheckpoint.wholeTree,
      `${reader} array continuation differs on an independent peer`);
    const history = await serverHistory(row.observer);
    const headAfter = await publishedVersion(config, row.documentId, row.jwt);
    assert.equal(headAfter, row.version, "Array reader unexpectedly changed the writer head");
    const item = {
      runId: context.runId,
      profileDigest: context.profileDigest,
      profile: "array",
      writer: row.writer,
      reader,
      writerVersion: row.version,
      loadedVersion: load.loadedVersion,
      readerInstanceId: adapter.instanceId,
      snapshotSequenceNumber: row.snapshotSequenceNumber,
      dataEditSequenceNumber: row.dataEditSequenceNumber,
      publicationSequenceNumber: row.publicationSequenceNumber,
      tailSequenceNumber: row.tailSequenceNumber,
      replayWatermark: continuationCheckpoint.sequenceNumber,
      replayStartSequenceNumber: load.replayStartSequenceNumber,
      replayEvidence: load.replayEvidence,
      selectedSummaryRequests: load.selectedSummaryRequests,
      scenarioId: "array-summary-tail-retained",
      loaded: true,
      tailObserved: true,
      continuedEditing: true,
      peerObservedEdit: true,
      pendingTreeCount: continuationCheckpoint.pendingTreeCount,
      inflightSubmissionCount: continuationCheckpoint.inflightSubmissionCount,
      wholeTree: loaded.wholeTree,
      continuationTree: continuationCheckpoint.wholeTree,
      peerWholeTree: peerCheckpoint.wholeTree,
      continuationLabel,
      documentId: row.documentId,
      writerVersionBeforeLoad: headBefore,
      writerVersionAfterLoad: headAfter,
      retained: {
        removed,
        reader,
        readerInstanceId: adapter.instanceId,
        source: reader === "upstream"
          ? "upstream-runtime-and-wire"
          : "native-runtime-snapshot",
        loadedVersion: load.loadedVersion,
        snapshotSequenceNumber: row.snapshotSequenceNumber,
        sequenceNumber: loaded.sequenceNumber,
        selectedVersion: load.loadedVersion,
        history: retainedHistory,
        moveIdentity: persistedMoveIdentity,
        childEditObserved: JSON.stringify(peerCheckpoint.wholeTree)
          .includes(continuationLabel),
        summaryConsumed: true,
      },
      continuationIdentity: continuationIdentity(
        history,
        adapter,
        continuation.outerSequenceNumber,
      ),
      artifacts: [],
    };
    item.artifacts = [await writeArrayReloadArtifact(context, item, {
      load: rawLoad,
      history,
      retained,
    })];
    await restoreArrayReader(adapter);
    await adapter.awaitSynced();
    return item;
  } catch (error) {
    readError = error;
    throw error;
  } finally {
    const cleanup = [];
    if (reader === "upstream") {
      for (const container of containers.toReversed()) {
        if (!container.closed) cleanup.push(() => container.dispose());
      }
    } else if (adapter) {
      cleanup.push(() => adapter.close());
      for (const container of containers.toReversed()) {
        if (!container.closed) cleanup.push(() => container.dispose());
      }
    }
    await cleanupAll(readError, `${reader} array reload reader cleanup failed`, cleanup);
  }
}

async function runArrayWriterRow(config, context, writer) {
  const containers = [];
  const natives = [];
  let rowError;
  try {
    const creator = await openSession(
      config,
      containers,
      undefined,
      false,
      { store: arrayServiceStore },
    );
    const documentId = creator.container.resolvedUrl.id;
    await publishUpstreamSummary(
      config,
      containers,
      documentId,
      `M3 ${writer} bootstrap`,
      { store: arrayServiceStore },
    );
    const bootstrapSummarizer = containers.at(-1);
    if (bootstrapSummarizer !== creator.container) bootstrapSummarizer.dispose();
    const upstreamSession = await openSession(
      config,
      containers,
      documentId,
      false,
      { store: arrayServiceStore },
    );
    const upstream = upstreamAdapter(upstreamSession);
    const creatorAdapter = upstreamAdapter(creator);
    const { jwt } = await tokenProvider(config).fetchOrdererToken(
      config.tenantId,
      documentId,
    );
    for (const target of nativeTargets) {
      natives.push(await nativeAdapter(target, config, {
        runId: context.runId,
        documentId,
        tenant: config.tenantId,
        viewSchema: context.arrayViewSchema,
      }, jwt));
    }
    const adapters = {
      upstream,
      javascript: natives[0],
      erlang: natives[1],
    };
    await settle(adapters);
    await adapters[writer].arrayInsert(["left"], 0, [
      arrayPointValue("duplicate", 1),
      arrayPointValue("duplicate", 1),
      arrayItemsValue([arrayPointValue("nested", 2)]),
      arrayPointValue("moved", 4),
      arrayPointValue("deleted", 9),
    ]);
    await adapters[writer].arrayInsert(["right"], 0, [
      arrayMapValue([["inside", arrayPointValue("map-child", 3)]]),
    ]);
    await adapters[writer].mapSet(["byKey"], "", arrayItemsValue([]));
    await adapters[writer].mapSet(
      ["byKey"],
      "0",
      arrayItemsValue([arrayPointValue("numeric", 0)]),
    );
    await adapters[writer].awaitSynced();
    await settle(adapters);
    const moveBaseline = (await adapters[writer].checkpoint()).sequenceNumber;
    await adapters[writer].arrayMove(["left"], 3, 4, ["right"], 1);
    await adapters[writer].awaitSynced();
    const selectedMove = await acknowledgedSubmission(
      creator,
      adapters[writer],
      moveBaseline,
      writer,
    );
    await adapters[writer].arrayRemove(["left"], 3, 4);
    await adapters[writer].awaitSynced();
    await settle(adapters);
    const tailValue = arrayPointValue(`after-summary-${writer}`, 7);
    const publication = await publishWriterSummary(
      config,
      containers,
      creator,
      documentId,
      jwt,
      writer,
      adapters,
      {
        store: arrayServiceStore,
        tailEdit: (adapter) => adapter.arrayInsert(["right"], 2, [tailValue]),
      },
    );

    for (const native of natives.toReversed()) await native.close();
    natives.length = 0;
    if (!upstream.session.container.closed) upstream.session.container.dispose();

    creator.data.bootstrap.set("historyFence", `array-after-${writer}-${randomUUID()}`);
    await until(() => !creator.container.isDirty, `${writer} array non-tree tail`);
    const tailHistory = await serverHistory(creator);
    const tail = tailHistory.findLast(({ clientId, sequenceNumber, type }) =>
      clientId === creator.container.clientId
        && sequenceNumber > publication.publicationSequenceNumber
        && type === "op");
    assert(tail, `${writer} lacks an array non-tree tail after publication`);

    const row = {
      writer,
      documentId,
      jwt,
      observer: creator,
      observerAdapter: creatorAdapter,
      tailSequenceNumber: tail.sequenceNumber,
      tailValue,
      selectedMoveHistory: submissionHistory(selectedMove),
      ...publication,
    };
    const results = {};
    for (const reader of implementations) {
      results[reader] = await readArrayCell(config, context, row, reader);
    }
    return results;
  } catch (error) {
    rowError = error;
    throw error;
  } finally {
    const cleanupErrors = [];
    for (const native of natives.toReversed()) {
      try {
        await native.close();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    for (const container of containers.toReversed()) {
      try {
        if (!container.closed) container.dispose();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    if (cleanupErrors.length > 0) {
      if (rowError) rowError.cleanupErrors = cleanupErrors;
      else throw new AggregateError(
        cleanupErrors,
        `Cleanup failed for ${writer} array reload row`,
      );
    }
  }
}

async function runMapWriterRow(config, context, writer) {
  const containers = [];
  const natives = [];
  let rowError;
  try {
    const creator = await openSession(
      config,
      containers,
      undefined,
      false,
      { store: mapServiceStore },
    );
    const documentId = creator.container.resolvedUrl.id;
    await publishUpstreamSummary(
      config,
      containers,
      documentId,
      `M2 ${writer} bootstrap`,
      { store: mapServiceStore },
    );
    const bootstrapSummarizer = containers.at(-1);
    if (bootstrapSummarizer !== creator.container) bootstrapSummarizer.dispose();
    const upstream = upstreamAdapter(await openSession(
      config,
      containers,
      documentId,
      false,
      { store: mapServiceStore },
    ));
    const creatorAdapter = upstreamAdapter(creator);
    const { jwt } = await tokenProvider(config).fetchOrdererToken(
      config.tenantId,
      documentId,
    );
    for (const target of nativeTargets) {
      natives.push(await nativeAdapter(target, config, {
        runId: context.runId,
        documentId,
        tenant: config.tenantId,
        viewSchema: context.mapViewSchema,
      }, jwt));
    }
    const adapters = {
      upstream,
      javascript: natives[0],
      erlang: natives[1],
    };
    await settle(adapters);
    const values = [
      ["", { kind: "string", value: "empty" }],
      ["123", { kind: "number", value: 123 }],
      ["__proto__", { kind: "null" }],
      ["point", mapPointValue(3, 4)],
      ["nested", dynamicMapValue([
        ["inner", { kind: "string", value: "nested" }],
        ["recursive", dynamicMapValue([
          ["leaf", { kind: "boolean", value: true }],
        ])],
      ])],
      ["水", { kind: "boolean", value: true }],
      ["deleted", mapPointValue(42, 7)],
    ];
    for (const [key, value] of values) {
      await adapters[writer].mapSet(["items"], key, value);
    }
    await adapters[writer].mapDelete(["items"], "deleted");
    await adapters[writer].awaitSynced();
    await settle(adapters);
    assert.equal((await adapters[writer].mapGet(["items"], "deleted")).present, false,
      `${writer} did not delete the retained map entry`);

    const tailValue = {
      kind: "string",
      value: `after-summary-${writer}`,
    };
    const publication = await publishWriterSummary(
      config,
      containers,
      creator,
      documentId,
      jwt,
      writer,
      adapters,
      {
        store: mapServiceStore,
        tailEdit: (adapter) => adapter.mapSet(["items"], "tail", tailValue),
      },
    );

    for (const native of natives.toReversed()) await native.close();
    natives.length = 0;
    if (!upstream.session.container.closed) upstream.session.container.dispose();

    creator.data.bootstrap.set("historyFence", `map-after-${writer}-${randomUUID()}`);
    await until(() => !creator.container.isDirty, `${writer} map non-tree tail`);
    const tailHistory = await serverHistory(creator);
    const tail = tailHistory.findLast(({ clientId, sequenceNumber, type }) =>
      clientId === creator.container.clientId
        && sequenceNumber > publication.publicationSequenceNumber
        && type === "op");
    assert(tail, `${writer} lacks a map non-tree tail after publication`);

    const verifier = await openSession(
      config,
      containers,
      documentId,
      false,
      { cache: false, observeStorage: true, store: mapServiceStore },
    );
    const retainedLoad = storageLoad(verifier.storageObservations, publication.version);
    assert(retainedLoad.replayStartSequenceNumber >= publication.snapshotSequenceNumber,
      "Map retained verifier replayed from the document origin");
    assert.equal(verifier.data.view.root.items.has("deleted"), false,
      "Fresh map retained read restored the deleted entry");
    assert.equal(verifier.data.view.root.items.has("tail"), true,
      "Fresh map retained read missed the summary tail");
    const removed = verifier.data.tree.contentSnapshot().removed;
    assert(removed.length > 0, "Fresh map retained read omitted deleted content");
    const retained = {
      removed,
      deletedKey: "deleted",
      summaryConsumed: true,
    };
    verifier.container.dispose();

    const row = {
      writer,
      documentId,
      jwt,
      observer: creator,
      observerAdapter: creatorAdapter,
      retained,
      retainedLoad: verifier.storageObservations,
      tailSequenceNumber: tail.sequenceNumber,
      tailValue,
      ...publication,
    };
    const results = {};
    for (const reader of implementations) {
      results[reader] = await readMapCell(config, context, row, reader);
    }
    return results;
  } catch (error) {
    rowError = error;
    throw error;
  } finally {
    const cleanupErrors = [];
    for (const native of natives.toReversed()) {
      try {
        await native.close();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    for (const container of containers.toReversed()) {
      try {
        if (!container.closed) container.dispose();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    if (cleanupErrors.length > 0) {
      if (rowError) rowError.cleanupErrors = cleanupErrors;
      else throw new AggregateError(
        cleanupErrors,
        `Cleanup failed for ${writer} map reload row`,
      );
    }
  }
}

export async function runMapReloadMatrix(config, context, {
  runRow,
} = {}) {
  assert(typeof context?.runId === "string" && context.runId.length > 0,
    "runMapReloadMatrix context requires runId");
  assert(typeof context.profileDigest === "string"
    && /^[0-9a-f]{64}$/.test(context.profileDigest),
  "runMapReloadMatrix context requires profileDigest");
  assert(typeof context.mapViewSchema === "string" && context.mapViewSchema.length > 0,
    "runMapReloadMatrix context requires mapViewSchema");
  assert(typeof context.artifactDirectory === "string"
    && context.artifactDirectory.length > 0,
  "runMapReloadMatrix context requires artifactDirectory");
  const executeRow = runRow ?? runMapWriterRow;
  const results = {};
  for (const writer of implementations) {
    results[writer] = await executeRow(config, context, writer);
  }
  return validateMapResults(results);
}

function validateSchemaMatrix(results, summaryKind) {
  assert.deepEqual(Object.keys(results).sort(), [...implementations].sort(),
    "Schema reload matrix lacks a writer");
  for (const writer of implementations) {
    assert.deepEqual(Object.keys(results[writer]).sort(), [...implementations].sort(),
      `Schema reload matrix lacks a reader for ${writer}`);
    for (const reader of implementations) {
      const cell = results[writer][reader];
      assert.equal(cell.writer, writer, "Schema reload writer changed");
      assert.equal(cell.reader, reader, "Schema reload reader changed");
      assert.equal(cell.skipped, false, "Schema reload cell was skipped");
      assert(Array.isArray(cell.observations) && cell.observations.length > 0,
        "Schema reload cell has zero observations");
      for (const observation of cell.observations) {
        assert.equal(observation.compatibility?.canView, true,
          "Schema reload reader cannot view the stored schema");
        assert.equal(observation.compatibility?.isEquivalent, true,
          "Schema reload reader reported a non-equivalent schema");
        assert.equal(typeof observation.compatibility?.canUpgrade, "boolean",
          "Schema reload reader omitted upgrade compatibility");
        assert.equal(observation.openedView, "optional");
        for (const field of [
          "continuedEditing",
          "peerObservedEdit",
          "summaryConsumed",
          "replayedTail",
          "retainedPeer",
          "pendingSummaryUsedSequencedSchema",
        ]) {
          assert.equal(observation[field], true,
            `Schema reload ${writer}->${reader} lacks ${field}`);
        }
        assert(typeof observation.documentId === "string"
          && observation.documentId.length > 0,
        "Schema reload lacks a document");
        assert(typeof observation.readerInstanceId === "string"
          && observation.readerInstanceId.length > 0,
        "Schema reload lacks a fresh reader instance");
        assert(typeof observation.pendingWriterInstanceId === "string"
          && observation.pendingWriterInstanceId.length > 0,
        "Schema reload lacks the pending writer instance");
          assert.equal(observation.summaryKind, summaryKind,
            "Schema reload used another summary kind");
          const selectedStoredState = summaryKind === "post-upgrade"
            ? observation.upgradedStoredState
            : observation.pendingStoredState;
          assert(typeof observation.loadedVersion === "string"
            && observation.loadedVersion === selectedStoredState.version,
          "Schema reload did not load the required summary");
        assert(Array.isArray(observation.selectedSummaryRequests)
          && observation.selectedSummaryRequests.includes(observation.loadedVersion),
        "Schema reload did not select its summary version");
        assert(Array.isArray(observation.selectedTreeRequests)
          && observation.selectedTreeRequests.length > 0,
        "Schema reload did not select summary trees");
        assert(Array.isArray(observation.selectedBlobRequests)
          && observation.selectedBlobRequests.length > 0,
        "Schema reload did not read summary blobs");
        assert(Number.isSafeInteger(observation.pendingSummaryReferenceSequenceNumber)
          && Number.isSafeInteger(observation.schemaUpgradeSequenceNumber)
          && observation.schemaUpgradeSequenceNumber
            > observation.pendingSummaryReferenceSequenceNumber,
        "Schema reload lacks an upgrade-bearing tail");
        const pendingUpgradeRevisions =
          observation.pendingWriterCheckpoint?.history?.pending?.map(
            ({ revision }) => revision,
          ) ?? [];
        assert(pendingUpgradeRevisions.length > 0,
          "Schema reload lacks writer pending history");
        const acceptedUpgradeRevisions =
          observation.acceptedUpgrade?.commits?.filter(({ changeset }) =>
            changeset.some((change) => change?.schema !== undefined))
            .map(({ revision }) => revision) ?? [];
        const sameRevision = acceptedUpgradeRevisions.some((revision) =>
          pendingUpgradeRevisions.map(String).includes(String(revision)));
        const sameOriginator = observation.acceptedUpgrade?.commits?.some(
          ({ originatorId, changeset }) =>
            changeset.some((change) => change?.schema !== undefined)
            && observation.pendingWriterCheckpoint?.history?.pending?.some(
              (pending) => pending.originatorId === originatorId,
            ),
        );
        assert(sameRevision || sameOriginator,
          "Schema reload accepted upgrade does not match writer pending history");
        assert(observation.pendingWriterCheckpoint.history.pending.every(
          ({ changeset }) => changeset?.changeCount > 0
            && (typeof changeset.raw === "string"
              ? /SchemaChange|type.?[:=].?["']?schema/i.test(changeset.raw)
              : changeset.raw?.changes?.some(({ type }) => type === "schema")),
        ), "Schema reload pending operation is not a schema upgrade");
        assert.equal(observation.acceptedUpgrade.outerSequenceNumber,
          observation.schemaUpgradeSequenceNumber,
        "Schema reload accepted upgrade sequence changed");
        assert.equal(observation.pendingStoredState?.version,
          observation.pendingSummaryVersion,
        "Schema reload inspected another sequenced baseline summary");
        assert.equal(observation.pendingSummaryPublication?.version,
          observation.pendingSummaryVersion,
        "Schema reload publication names another pending summary version");
        assert(observation.pendingSummaryPublication?.snapshotSequenceNumber
          >= observation.pendingSummaryReferenceSequenceNumber,
        "Schema reload publication preceded the pending capture reference");
        assert(Number.isSafeInteger(
          observation.pendingSummaryPublication?.publicationSequenceNumber,
        ) && observation.pendingSummaryPublication.publicationSequenceNumber
          > observation.pendingSummaryReferenceSequenceNumber,
        "Schema reload lacks pending summary publication evidence");
        assert(observation.pendingPublicationVerification?.load
          ?.selectedSummaryRequests.includes(observation.pendingSummaryVersion),
        "Schema reload did not freshly load the pending summary version");
        assert.deepEqual(
          observation.pendingPublicationVerification.checkpoint.wholeTree,
          observation.captureSequencedCheckpoint.wholeTree,
        "Schema reload pending publication decoded another sequenced tree");
        assert.deepEqual(
          observation.pendingPublicationVerification.checkpoint.history.storedSchema,
          observation.captureSequencedCheckpoint.history.storedSchema,
        "Schema reload pending publication decoded another sequenced schema");
        assert.equal(observation.pendingSummaryCapture?.sequenceNumber,
          observation.pendingSummaryReferenceSequenceNumber,
        "Schema reload pending encoder used another sequence point");
        assert.equal(observation.upgradedStoredState?.version,
          observation.upgradedSummaryVersion,
        "Schema reload inspected another upgraded summary");
        const measuredBinding = pendingSummaryBinding(
          observation.pendingSummaryCapture,
          observation.pendingSummaryCaptureSourceBehavior
              === "upstream-optimistic-encoder-retained-future-state"
            ? observation.captureEncoderReference
            : observation.retainedEncoderReference,
          observation.sequencedEncoderReference,
        );
        assert.deepEqual(observation.pendingSummaryBinding, measuredBinding,
          "Schema reload pending encoder binding changed");
        assert.equal(observation.retainedEncoderReference.sequenceNumber,
          observation.acceptedRetainedPeer.outerSequenceNumber,
        "Schema reload retained encoder reference identifies another operation");
        assert.equal(observation.captureEncoderReference.sequenceNumber,
          observation.pendingSummaryReferenceSequenceNumber,
        "Schema reload capture encoder reference identifies another operation");
        assert([
          "stable-reference",
          "reference-advanced-without-tree-change",
          "upstream-optimistic-encoder-retained-future-state",
        ].includes(observation.pendingSummaryCaptureSourceBehavior),
        "Schema reload lacks pending capture source behavior");
        if (writer === "upstream") {
          assert.equal(observation.pendingSummaryCaptureSourceBehavior,
            "upstream-optimistic-encoder-retained-future-state",
          "Schema reload omitted upstream optimistic encoder behavior");
          assert(!isDeepStrictEqual(
            JSON.parse(observation.pendingSummaryInitialCapture.schema.content),
            JSON.parse(observation.pendingSummaryCapture.schema.content),
          ), "Schema reload did not preserve upstream optimistic encoder evidence");
        } else {
          assert.deepEqual(
            JSON.parse(observation.pendingSummaryInitialCapture.schema.content),
            JSON.parse(observation.pendingSummaryCapture.schema.content),
          "Schema reload native pending schema changed while its reference advanced");
          assert(sameBlobContents(
            observation.pendingSummaryInitialCapture.forest,
            observation.pendingSummaryCapture.forest,
          ), "Schema reload native pending forest changed while its reference advanced");
        }
        assert(observation.sequencedWriterCheckpoint?.sequenceNumber
            >= observation.schemaUpgradeSequenceNumber
          && observation.sequencedWriterCheckpoint.pendingTreeCount === 0,
        "Schema reload encoder reference precedes upgrade reconciliation");
        assert(typeof observation.pendingStoredState.rootTreeId === "string"
          && observation.pendingStoredState.treeIds?.includes(
            observation.pendingStoredState.rootTreeId,
          ),
        "Schema reload stored-state tree is not bound to the selected version");
        for (const [name, blob] of [["schema", observation.pendingStoredState.schema]]) {
          assert(typeof blob?.id === "string" && blob.id.length > 0
            && Number.isSafeInteger(blob.byteLength) && blob.byteLength > 0
            && typeof blob.hash === "string" && /^[0-9a-f]{64}$/.test(blob.hash)
            && typeof blob.content === "string" && blob.content.length > 0,
          `Schema reload stored ${name} blob is incomplete`);
        }
        assert(typeof observation.pendingStoredState.forest?.treeId === "string"
          && observation.pendingStoredState.treeIds.includes(
            observation.pendingStoredState.forest.treeId,
          )
          && observation.pendingStoredState.forest.blobs?.length > 0
          && observation.pendingStoredState.forest.blobs.every((blob) =>
            typeof blob.id === "string" && blob.id.length > 0
              && Number.isSafeInteger(blob.byteLength) && blob.byteLength > 0
              && typeof blob.hash === "string" && /^[0-9a-f]{64}$/.test(blob.hash)
              && typeof blob.content === "string" && blob.content.length > 0),
        "Schema reload stored forest evidence is incomplete");
        assert.deepEqual(JSON.parse(observation.pendingStoredState.schema.content),
          JSON.parse(observation.pendingSummaryCapture.schema.content),
        "Schema reload pending publication differs from captured schema");
        const acceptedSchemaChange = observation.acceptedUpgrade.commits
          .flatMap(({ changeset }) => changeset)
          .find((change) => change?.schema !== undefined);
        assert.deepEqual(JSON.parse(observation.pendingStoredState.schema.content),
          acceptedSchemaChange.schema.old,
        "Schema reload stored pending schema instead of historical schema");
        assert.deepEqual(JSON.parse(observation.upgradedStoredState.schema.content),
          acceptedSchemaChange.schema.new,
        "Schema reload stored summary omitted the upgraded schema context");
        const retainedPendingRevisions =
          observation.retainedPeerCheckpoint?.history?.pending?.map(
            ({ revision }) => revision,
          ) ?? [];
        assert(retainedPendingRevisions.length > 0,
          "Schema reload lacks retained peer pending history");
        assert(observation.acceptedRetainedPeer?.commits?.some(({ changeset }) =>
          changeset.some((change) => change?.data !== undefined)),
        "Schema reload accepted peer history lacks its data change");
        assert.equal(observation.retainedPeerAuthor,
          writer === "upstream" ? "javascript" : "upstream",
        "Schema reload retained the wrong earlier-schema peer");
        assert(observation.freshLoadCheckpoint.history.trunk.length > 0,
          "Schema reload fresh reader history is empty");
        assert(observation.beforeContinuation.history.trunk.length > 0,
          "Schema reload pre-continuation history is empty");
        const retainedCommit = observation.acceptedRetainedPeer.commits.find(
          ({ changeset }) => changeset.some((change) => change.data !== undefined),
        );
        const upgradeCommit = observation.acceptedUpgrade.commits.find(
          ({ changeset }) => changeset.some((change) => change.schema !== undefined),
        );
        assert(retainedCommit && upgradeCommit,
          "Schema reload lacks accepted retained and upgrade operations");
        if (summaryKind === "post-upgrade") {
          validatePostUpgradeHistory(
            observation.freshLoadCheckpoint.history,
            upgradeCommit,
            "Schema reload post-upgrade fresh-reader history",
          );
          validatePostUpgradeHistory(
            observation.beforeContinuation.history,
            upgradeCommit,
            "Schema reload post-upgrade pre-continuation history",
          );
        }
        const retainedPending = observation.retainedPeerCheckpoint.history.pending.find(
          ({ originatorId, changeset }) =>
            originatorId === retainedCommit.originatorId
            && changeset?.changeCount > 0,
        );
        assert(retainedPending
          && isDeepStrictEqual(
            decodeReconnectPayload(
              retainedPending.changeset.payload ?? retainedPending.changeset.raw,
            ),
            decodeReconnectPayload(retainedCommit.changeset),
          ),
        "Schema reload retained pending history differs from its accepted operation");
        if (summaryKind === "earlier-summary-upgrade-tail") {
          for (const [historyLabel, history] of [
            ["fresh-load", observation.freshLoadCheckpoint.history],
            ["pre-continuation", observation.beforeContinuation.history],
          ]) {
            assert(historyContains(history, upgradeCommit, "schema"),
              `Schema reload ${writer}->${reader} ${historyLabel} history `
                + "omitted the accepted schema operation");
          }
        }
        assert(observation.upgradedStoredState.forest.blobs.some(({ content }) =>
          content.includes(`retained-${writer}`)),
        "Schema reload stored summary omitted the retained peer value");
        assert(observation.beforeContinuation.wholeTree.value.fields.some(
          ([name, field]) =>
            name === "title" && field.value === `retained-${writer}`,
        ), "Schema reload fresh reader omitted the retained peer value");
        const storedTreeIds = new Set(selectedStoredState.treeIds);
        assert(observation.selectedTreeRequests.length > 0
          && observation.selectedTreeRequests.every((request) =>
            storedTreeIds.has(typeof request === "string" ? request : request.id)),
        "Schema reload requested an unrelated summary tree");
        if (typeof observation.selectedSummaryTreeId === "string") {
          assert.equal(observation.selectedSummaryTreeId,
            selectedStoredState.rootTreeId,
          "Schema reload selected another summary tree");
          assert(observation.selectedTreeRequests.includes(
            observation.selectedSummaryTreeId,
          ), "Schema reload did not request the selected summary tree");
        }
        const storedBlobIds = new Set([
          ...selectedStoredState.blobIds,
        ]);
        assert(observation.selectedBlobRequests.length > 0
          && observation.selectedBlobRequests.every((request) =>
            storedBlobIds.has(typeof request === "string" ? request : request.id)),
        "Schema reload requested unrelated summary blobs");
        assert(observation.acceptedRetainedPeer.outerSequenceNumber
          <= observation.pendingSummaryReferenceSequenceNumber,
        "Schema reload retained peer was not accepted before pending capture");
        assert(observation.acceptedRetainedPeer.outerSequenceNumber
            < observation.schemaUpgradeSequenceNumber
            && observation.acceptedRetainedPeer.outerSequenceNumber
              <= observation.snapshotSequenceNumber,
          "Schema reload retained peer was not accepted before upgraded summary capture");
          if (summaryKind === "earlier-summary-upgrade-tail") {
            assert(observation.snapshotSequenceNumber
                < observation.schemaUpgradeSequenceNumber
              && observation.replayWatermark
                >= observation.schemaUpgradeSequenceNumber,
            "Schema reload did not cross the schema boundary from the earlier summary");
          }
            assert(observation.freshLoadCheckpoint?.history
              && observation.beforeContinuation?.history,
          "Schema reload lacks fresh pre-continuation state");
      }
    }
  }
  return results;
}

export function validateSchemaReloadResults(results) {
  return validateSchemaMatrix(results, "post-upgrade");
}

export function validateSchemaTailReloadResults(results) {
  return validateSchemaMatrix(results, "earlier-summary-upgrade-tail");
}

async function schemaReader(config, context, row, reader) {
  const containers = [];
  let adapter;
  let failure;
  try {
    if (reader === "upstream") {
      const session = await openSession(
        config,
        containers,
        row.documentId,
        false,
        {
          cache: false,
          observeStorage: true,
          store: schemaEvolutionServiceStore,
        },
      );
      adapter = upstreamAdapter(session, schemaEvolutionConfigurations);
      await adapter.awaitSynced(row.replayWatermark);
    } else {
      adapter = await nativeAdapter(reader, config, {
        runId: context.runId,
        documentId: row.documentId,
        tenant: config.tenantId,
        viewSchema: context.schemaViews.optional,
        viewSchemas: context.schemaViews,
      }, row.jwt);
      await adapter.awaitSynced(row.publicationSequenceNumber);
    }
    const freshLoadCheckpoint = await adapter.checkpoint();
    const rawLoad = reader === "upstream"
      ? adapter.session.storageObservations
      : adapter.evidence();
    const load = reader === "upstream"
      ? storageLoad(rawLoad, row.version)
      : loadRequests(rawLoad, row.version, row.snapshotSequenceNumber);
    const compatibility = await adapter.schemaCompatibility("optional");
    assert.equal(compatibility.canView, true,
      `${reader} did not replay the upgrade-bearing tail`);
    await adapter.openView("optional");
    const beforeContinuation = await adapter.checkpoint();
    assert(beforeContinuation.wholeTree.value.fields.some(([name, field]) =>
      name === "note" && field.value === row.tailNote),
    `${reader} did not replay the schema tail before continuation`);
    assert(beforeContinuation.wholeTree.value.fields.some(([name, field]) =>
      name === "title" && field.value === `retained-${row.writer}`),
    `${reader} did not load the retained peer value before continuation`);
    const value = 1000 + implementations.indexOf(reader);
    await adapter.set(["score"], value);
    await adapter.awaitSynced();
    await row.observerAdapter.openView("optional");
    await row.observerAdapter.awaitSynced();
    const observed = await row.observerAdapter.checkpoint();
    assert(observed.wholeTree.value.fields.some(([name, field]) =>
      name === "score" && field.value === value),
    `${row.writer} schema reload continuation was not observed`);
    return {
      writer: row.writer,
      reader,
      skipped: false,
      observations: [{
        compatibility,
        freshLoadCheckpoint,
        beforeContinuation,
        openedView: "optional",
        continuedEditing: true,
        peerObservedEdit: true,
        summaryConsumed: load.selectedSummaryRequests.includes(row.version),
        replayedTail: observed.wholeTree.value.fields.some(([name, field]) =>
          name === "note" && field.value === row.tailNote),
        retainedPeer: row.retainedPeer,
        retainedPeerAuthor: row.retainedPeerAuthor,
        pendingSummaryUsedSequencedSchema: row.pendingSummaryUsedSequencedSchema,
        pendingSummaryVersion: row.pendingSummaryVersion,
        pendingSummaryPublication: row.pendingSummaryPublication,
        pendingPublicationVerification: row.pendingPublicationVerification,
        captureSequencedCheckpoint: row.captureSequencedCheckpoint,
        pendingSummaryReferenceSequenceNumber:
          row.pendingSummaryReferenceSequenceNumber,
        pendingSummaryCapture: row.pendingSummaryCapture,
        pendingSummaryInitialCapture: row.pendingSummaryInitialCapture,
        pendingSummaryCaptureSourceBehavior:
          row.pendingSummaryCaptureSourceBehavior,
        captureEncoderReference: row.captureEncoderReference,
        retainedEncoderReference: row.retainedEncoderReference,
        sequencedEncoderReference: row.sequencedEncoderReference,
        pendingSummaryBinding: row.pendingSummaryBinding,
        upgradedSummaryVersion: row.version,
        schemaUpgradeSequenceNumber: row.schemaUpgradeSequenceNumber,
        acceptedUpgrade: row.acceptedUpgrade,
        sequencedWriterCheckpoint: row.sequencedWriterCheckpoint,
        retainedPeerCheckpoint: row.retainedPeerCheckpoint,
        acceptedRetainedPeer: row.acceptedRetainedPeer,
        pendingWriterInstanceId: row.pendingWriterInstanceId,
        pendingWriterCheckpoint: row.pendingWriterCheckpoint,
        pendingStoredState: row.pendingStoredState,
        upgradedStoredState: row.upgradedStoredState,
        summaryKind: row.summaryKind,
        snapshotSequenceNumber: row.snapshotSequenceNumber,
        publicationSequenceNumber: row.publicationSequenceNumber,
        dataEditSequenceNumber: row.dataEditSequenceNumber,
        replayWatermark: beforeContinuation.sequenceNumber,
        documentId: row.documentId,
        loadedVersion: load.loadedVersion,
        selectedSummaryRequests: load.selectedSummaryRequests,
        selectedSummaryTreeId: load.selectedSummaryTreeId,
        selectedTreeRequests: load.selectedTreeRequests,
        selectedBlobRequests: load.selectedBlobRequests,
        replayStartSequenceNumber: load.replayStartSequenceNumber,
        replayEvidence: load.replayEvidence,
        readerInstanceId: adapter.instanceId,
      }],
    };
  } catch (error) {
    failure = error;
    throw error;
  } finally {
    const cleanupErrors = [];
    if (reader !== "upstream" && adapter) {
      try {
        await adapter.close();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    for (const container of containers.toReversed()) {
      try {
        if (!container.closed) container.dispose();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    if (cleanupErrors.length > 0) {
      if (failure) failure.cleanupErrors = cleanupErrors;
      else throw new AggregateError(cleanupErrors, "Schema reader cleanup failed");
    }
  }
}

async function runSchemaWriterRow(config, context, writer) {
  const containers = [];
  const natives = [];
  let failure;
  try {
    const creator = await openSession(config, containers, undefined, false, {
      store: schemaEvolutionServiceStore,
    });
    const documentId = creator.container.resolvedUrl.id;
    await publishUpstreamSummary(
      config,
      containers,
      documentId,
      `Task 10 ${writer} schema bootstrap`,
      { store: schemaEvolutionServiceStore },
    );
    const upstreamSession = await openSession(
      config,
      containers,
      documentId,
      writer === "upstream",
      { store: schemaEvolutionServiceStore },
    );
    if (writer === "upstream") {
      const rootHandle =
        await upstreamSession.runtime.getAliasedDataStoreEntryPoint(rootDataStoreId);
      assert(rootHandle, "Upstream summarizer lacks the schema data store");
      upstreamSession.summarizer = upstreamSession.data.ISummarizer;
      upstreamSession.data = await rootHandle.get();
    }
    const upstream = upstreamAdapter(upstreamSession, schemaEvolutionConfigurations);
    const observerAdapter = upstreamAdapter(creator, schemaEvolutionConfigurations);
    const { jwt } = await tokenProvider(config).fetchOrdererToken(
      config.tenantId,
      documentId,
    );
    for (const target of nativeTargets) {
      natives.push(await nativeAdapter(target, config, {
        runId: context.runId,
        documentId,
        tenant: config.tenantId,
        viewSchema: context.schemaViews.v1,
        viewSchemas: context.schemaViews,
      }, jwt));
    }
    const adapters = {
      upstream,
      javascript: natives[0],
      erlang: natives[1],
    };
    await settle(adapters);

    const retainedPeerAuthor = writer === "upstream" ? "javascript" : "upstream";
    await adapters[retainedPeerAuthor].holdOutbound();
    await adapters[retainedPeerAuthor].set(["title"], `retained-${writer}`);
    const retainedPeerCheckpoint = await adapters[retainedPeerAuthor].checkpoint();
    assert(retainedPeerCheckpoint.pendingTreeCount > 0,
      `${writer} lacks a retained pre-upgrade peer branch`);
    await adapters[retainedPeerAuthor].releaseOutbound({
      order: "fifo",
      duplicate: false,
    });
    const acceptedRetainedPeer = await waitForAuthorSubmission(
      creator,
      adapters,
      retainedPeerAuthor,
      retainedPeerCheckpoint.sequenceNumber,
      1,
    );
    await Promise.all(implementations.map((target) =>
      adapters[target].awaitSynced(acceptedRetainedPeer.outerSequenceNumber)));
    const retainedEncoderReference = pendingSummaryCapture(
      await adapters[writer].pendingSummaryEvidence(),
    );
    assert.equal(
      retainedEncoderReference.sequenceNumber,
      acceptedRetainedPeer.outerSequenceNumber,
      `${writer} retained encoder reference used another sequence point`,
    );

    await adapters[writer].holdOutbound();
    await adapters[writer].schemaUpgrade("optional");
    await adapters[writer].openView("optional");
    const pending = await adapters[writer].checkpoint();
    assert(pending.pendingTreeCount > 0, `${writer} schema upgrade was not pending`);
    const initialPendingCapture = pendingSummaryCapture(
      await adapters[writer].pendingSummaryEvidence(),
    );
    assert.equal(initialPendingCapture.sequenceNumber, pending.sequenceNumber,
      `${writer} pending summary capture used another sequence point`);
    await observerAdapter.awaitSynced(pending.sequenceNumber);
    const captureSequencedCheckpoint = await observerAdapter.checkpoint();
    const captureEncoderReference = pendingSummaryCapture(
      await observerAdapter.pendingSummaryEvidence(),
    );
    const pendingPublication = await publishPendingSchemaSummary(
      config,
      containers,
      documentId,
      jwt,
      writer,
      adapters,
      context,
    );
    assert(Number.isSafeInteger(pendingPublication.snapshotSequenceNumber),
    `${writer} pending summary publication lacks a sequence point`);
    let pendingCapture;
    let pendingSummaryCaptureSourceBehavior;
    if (writer === "upstream") {
      pendingCapture = captureEncoderReference;
      pendingSummaryCaptureSourceBehavior =
        "upstream-optimistic-encoder-retained-future-state";
    } else {
      pendingCapture = initialPendingCapture;
      pendingSummaryCaptureSourceBehavior = "stable-reference";
    }
    assert(pendingPublication.snapshotSequenceNumber
      >= pendingCapture.sequenceNumber,
    `${writer} pending publication preceded the capture reference`);
    const pendingStoredState = await publishedSchemaSnapshot(
      config,
      documentId,
      jwt,
      pendingPublication.version,
    );
    const pendingSummaryReferenceSequenceNumber = pendingCapture.sequenceNumber;
    assert(Number.isSafeInteger(pendingSummaryReferenceSequenceNumber),
      `${writer} pending summary capture lacks a reference sequence number`);
    assert.deepEqual(JSON.parse(pendingStoredState.schema.content),
      JSON.parse(context.schemaViews.v1),
      `${writer} pending summary did not store the sequenced schema`);
    assert.deepEqual(JSON.parse(pendingStoredState.schema.content),
      JSON.parse(pendingCapture.schema.content),
    `${writer} pending publication differs from the captured schema`);
    const pendingPublicationVerification = await verifyPendingSchemaPublication(
      config,
      containers,
      documentId,
      pendingPublication.version,
      pendingPublication.snapshotSequenceNumber,
    );
    assert.deepEqual(pendingPublicationVerification.checkpoint.wholeTree,
      captureSequencedCheckpoint.wholeTree,
    `${writer} pending publication decoded another sequenced tree state`);
    assert.deepEqual(
      pendingPublicationVerification.checkpoint.history.storedSchema,
      captureSequencedCheckpoint.history.storedSchema,
    `${writer} pending publication decoded another sequenced schema`);
    await adapters[writer].releaseOutbound({ order: "fifo", duplicate: false });
    const acceptedUpgrade = await waitForAuthorSubmission(
      creator,
      adapters,
      writer,
      pending.sequenceNumber,
      1,
    );
    await adapters[writer].awaitSynced(acceptedUpgrade.outerSequenceNumber);
    let sequencedWriterCheckpoint;
    await until(async () => {
      sequencedWriterCheckpoint = await adapters[writer].checkpoint();
      return sequencedWriterCheckpoint.sequenceNumber
          >= acceptedUpgrade.outerSequenceNumber
        && sequencedWriterCheckpoint.pendingTreeCount === 0;
    }, `${writer} accepted upgrade reconciliation`);
    const sequencedEncoderReference = pendingSummaryCapture(
      await adapters[writer].pendingSummaryEvidence(),
    );
    assert(
      sequencedEncoderReference.sequenceNumber
        >= acceptedUpgrade.outerSequenceNumber,
      `${writer} encoder reference preceded the sequenced upgrade`,
    );
    const binding = pendingSummaryBinding(
      pendingCapture,
      writer === "upstream"
        ? captureEncoderReference
        : retainedEncoderReference,
      sequencedEncoderReference,
    );
    await Promise.all(implementations.map((target) => adapters[target].awaitSynced()));
    const settledUpgrade = await adapters[writer].checkpoint();
    assert(settledUpgrade.sequenceNumber > pendingSummaryReferenceSequenceNumber,
      `${writer} schema upgrade did not sequence after the pending summary`);
    await Promise.all(implementations.map((target) =>
      adapters[target].openView("optional")));
    await adapters[writer].set(["score"], 10 + implementations.indexOf(writer));
    await settle(adapters);

    const tailNote = `schema-tail-${writer}`;
    await adapters[writer].set(["note"], tailNote);
    const tailCheckpoint = await settle(adapters);
    const commonRow = {
      writer,
      documentId,
      jwt,
      observerAdapter,
      tailNote,
      retainedPeer: true,
      retainedPeerAuthor,
      retainedPeerCheckpoint,
      acceptedRetainedPeer,
      pendingSummaryUsedSequencedSchema: true,
      pendingSummaryVersion: pendingPublication.version,
      pendingSummaryPublication: pendingPublication,
      pendingPublicationVerification,
      captureSequencedCheckpoint,
      pendingSummaryReferenceSequenceNumber,
      pendingSummaryCapture: pendingCapture,
      pendingSummaryInitialCapture: initialPendingCapture,
      pendingSummaryCaptureSourceBehavior,
      captureEncoderReference,
      retainedEncoderReference,
      sequencedEncoderReference,
      pendingSummaryBinding: binding,
      schemaUpgradeSequenceNumber: acceptedUpgrade.outerSequenceNumber,
      acceptedUpgrade,
      sequencedWriterCheckpoint,
      pendingWriterInstanceId: adapters[writer].instanceId,
      pendingWriterCheckpoint: pending,
      pendingStoredState,
      replayWatermark: tailCheckpoint.observations[0].sequenceNumber,
    };
    const earlierRow = {
      ...commonRow,
      summaryKind: "earlier-summary-upgrade-tail",
      upgradedStoredState: pendingStoredState,
      version: pendingPublication.version,
      snapshotSequenceNumber: pendingPublication.snapshotSequenceNumber,
      publicationSequenceNumber: pendingPublication.publicationSequenceNumber,
      dataEditSequenceNumber: acceptedRetainedPeer.outerSequenceNumber,
      tailSequenceNumber: tailCheckpoint.observations[0].sequenceNumber,
    };
    const earlierSummary = {};
    for (const reader of implementations) {
      earlierSummary[reader] = await schemaReader(config, context, earlierRow, reader);
    }
    const publication = await publishWriterSummary(
      config,
      containers,
      creator,
      documentId,
      jwt,
      writer,
      adapters,
      {
        store: schemaEvolutionServiceStore,
        tailEdit: (adapter) => adapter.set(
          ["note"],
          `${tailNote}-post-summary`,
        ),
      },
    );
    const upgradedStoredState = await publishedSchemaSnapshot(
      config,
      documentId,
      jwt,
      publication.version,
    );
    assert.deepEqual(JSON.parse(upgradedStoredState.schema.content),
      JSON.parse(context.schemaViews.optional),
      `${writer} upgraded summary did not store the upgraded schema`);
    assert(upgradedStoredState.forest.blobs.some(({ content }) =>
      content.includes(`retained-${writer}`)),
    `${writer} upgraded summary omitted the retained peer value`);
    for (const item of Object.values(earlierSummary)) {
      item.observations[0].upgradedStoredState = upgradedStoredState;
      item.observations[0].upgradedSummaryVersion = publication.version;
    }
    const retainedPeerRevisions = retainedPeerCheckpoint.history?.pending?.map(
      ({ revision }) => String(revision),
    ) ?? [];
    assert(acceptedRetainedPeer,
      `${writer} retained peer commit is missing from accepted history: ${JSON.stringify({
        retainedPeerAuthor,
        retainedPeerRevisions,
        clientIds: [...adapters[retainedPeerAuthor].clientIds],
      })}`);
    for (const native of natives.toReversed()) await native.close();
    natives.length = 0;
    if (!upstream.session.container.closed) upstream.session.container.dispose();

    const row = {
      ...commonRow,
      summaryKind: "post-upgrade",
      tailNote: `${tailNote}-post-summary`,
      upgradedStoredState,
      version: publication.version,
      snapshotSequenceNumber: publication.snapshotSequenceNumber,
      publicationSequenceNumber: publication.publicationSequenceNumber,
      dataEditSequenceNumber: publication.dataEditSequenceNumber,
      tailSequenceNumber: publication.dataEditSequenceNumber,
      replayWatermark: publication.publicationSequenceNumber,
    };
    const postUpgrade = {};
    for (const reader of implementations) {
      postUpgrade[reader] = await schemaReader(config, context, row, reader);
    }
    return { postUpgrade, earlierSummary };
  } catch (error) {
    failure = error;
    throw error;
  } finally {
    const cleanupErrors = [];
    for (const native of natives.toReversed()) {
      try {
        await native.close();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    for (const container of containers.toReversed()) {
      try {
        if (!container.closed) container.dispose();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    if (cleanupErrors.length > 0) {
      if (failure) failure.cleanupErrors = cleanupErrors;
      else throw new AggregateError(cleanupErrors, "Schema writer cleanup failed");
    }
  }
}

export async function runSchemaReloadMatrix(config, context, {
  runRow = runSchemaWriterRow,
} = {}) {
  const results = {};
  for (const writer of implementations) {
    const row = await runRow(config, context, writer);
    results[writer] = row.postUpgrade ?? row;
  }
  return results;
}

export async function runSchemaReloadMatrices(config, context, {
  runRow = runSchemaWriterRow,
} = {}) {
  const postUpgrade = {};
  const earlierSummary = {};
  for (const writer of implementations) {
    const row = await runRow(config, context, writer);
    postUpgrade[writer] = row.postUpgrade;
    earlierSummary[writer] = row.earlierSummary;
  }
  return { postUpgrade, earlierSummary };
}

export async function runArrayReloadMatrix(config, context, {
  runRow,
} = {}) {
  assert(typeof context?.runId === "string" && context.runId.length > 0,
    "runArrayReloadMatrix context requires runId");
  assert(typeof context.profileDigest === "string"
    && /^[0-9a-f]{64}$/.test(context.profileDigest),
  "runArrayReloadMatrix context requires profileDigest");
  assert(typeof context.arrayViewSchema === "string" && context.arrayViewSchema.length > 0,
    "runArrayReloadMatrix context requires arrayViewSchema");
  assert(typeof context.artifactDirectory === "string"
    && context.artifactDirectory.length > 0,
  "runArrayReloadMatrix context requires artifactDirectory");
  const executeRow = runRow ?? runArrayWriterRow;
  const results = {};
  for (const writer of implementations) {
    results[writer] = await executeRow(config, context, writer);
  }
  return validateArrayResults(results);
}

function transactionPointValue(label, x) {
  return {
    kind: "object",
    schemaId: "org.watershed.shared-tree.m3.Point",
    fields: [
      ["label", { kind: "string", value: label }],
      ["x", { kind: "number", value: x }],
    ],
  };
}

function arrayFieldElements(checkpoint, field) {
  const entry = checkpoint.wholeTree?.value?.fields
    ?.find(([name]) => name === field)?.[1];
  assert(entry?.kind === "array", `Array checkpoint lacks the ${field} field`);
  return entry.elements;
}

function arrayFieldLabels(checkpoint, field) {
  return arrayFieldElements(checkpoint, field).map((element) =>
    element?.fields?.find(([name]) => name === "label")?.[1]?.value ?? null);
}

// The restored commit history a reader exposes after it loads a summary. The
// upstream reader keeps the retained trunk in its edit manager. A native reader
// evicts the trunk below its sequenced base and keeps the loaded commits in its
// retained wire history, so both sources belong to the same claim.
function restoredHistoryCommits(checkpoint) {
  return [
    ...(checkpoint.history?.trunk ?? []),
    ...(checkpoint.retained?.history ?? []),
  ];
}

// Counts the restored commits that carry every label of the writer's composed
// transaction, and the restored commits that carry only part of it. A reader
// that rebuilt the transaction as one commit reports at least one composed
// commit and no partial commit.
function writerCommitEvidence(checkpoint, labels) {
  const counts = restoredHistoryCommits(checkpoint).map((entry) => {
    const text = JSON.stringify(entry);
    return labels.filter((label) => text.includes(label)).length;
  });
  return {
    composedCommitCount: counts.filter((count) => count === labels.length).length,
    partialCommitCount: counts
      .filter((count) => count > 0 && count < labels.length).length,
  };
}

export function validateTransactionReloadResults(results) {
  assert(results && typeof results === "object" && !Array.isArray(results),
    "Transaction summary interop needs a nested reload matrix");
  assert.deepEqual(Object.keys(results).sort(), [...implementations].sort(),
    "Transaction summary interop needs all three writers");
  const readerInstances = new Set();
  for (const writer of implementations) {
    assert.deepEqual(Object.keys(results[writer] ?? {}).sort(),
      [...implementations].sort(),
      `Transaction summary interop needs all three readers for ${writer}`);
    for (const reader of implementations) {
      const cell = results[writer][reader];
      assert(cell && typeof cell === "object",
        `Transaction reload lacks ${writer}->${reader}`);
      assert.equal(cell.profile, "array", "Transaction reload has another profile");
      assert.equal(cell.writer, writer, "Invalid transaction writer identity");
      assert.equal(cell.reader, reader, "Invalid transaction reader identity");
      assert(typeof cell.runId === "string" && cell.runId.length > 0,
        "Missing transaction reload run ID");
      assert.match(cell.profileDigest ?? "", /^[0-9a-f]{64}$/,
        "Missing transaction reload profile digest");
      assert(typeof cell.documentId === "string" && cell.documentId.length > 0,
        "Missing transaction reload document ID");
      assert(typeof cell.writerVersion === "string" && cell.writerVersion.length > 0,
        "Missing transaction writer version");
      assert.equal(cell.loadedVersion, cell.writerVersion,
        "Transaction reload selected another version");
      assert(typeof cell.readerInstanceId === "string"
        && cell.readerInstanceId.length > 0,
      "Missing transaction reload reader instance");
      assert(!readerInstances.has(cell.readerInstanceId),
        "Transaction reload reused a reader instance");
      readerInstances.add(cell.readerInstanceId);
      assert.equal(cell.scenarioId, "transaction-summary-postload",
        "Transaction reload used another scenario");
      assert.equal(cell.loaded, true, "Transaction reload did not load");
      assert.equal(cell.historyVerified, true,
        "Transaction reader did not verify history");
      assert(cell.historyEvidence && typeof cell.historyEvidence === "object",
        "Transaction reader lacks history evidence");
      assert.equal(cell.historyEvidence.pendingCount, 0,
        "Transaction reader restored pending commits");
      assert(Number.isInteger(cell.historyEvidence.trunkCount)
        && cell.historyEvidence.trunkCount >= 0,
      "Transaction reader lacks a restored trunk count");
      assert(Number.isInteger(cell.historyEvidence.composedCommitCount)
        && cell.historyEvidence.composedCommitCount >= 1,
      "Transaction reader did not restore the writer's composed commit");
      assert.equal(cell.historyEvidence.partialCommitCount, 0,
        "Transaction reader restored the writer's transaction in parts");
      assert.equal(cell.nodeIdentityVerified, true,
        "Transaction reader did not verify node identity");
      assert(cell.constrainedNode && typeof cell.constrainedNode === "object",
        "Transaction reload lacks the compared constrained node");
      assert.equal(cell.constrainedNode.field, "left",
        "The constrained node moved to another field");
      assert.equal(cell.constrainedNode.index, 0,
        "The constrained node moved to another position");
      assert.equal(cell.constrainedNode.label, "anchor",
        "The constrained node carries another label");
      assert(cell.constrainedNode.value
        && typeof cell.constrainedNode.value === "object",
      "The constrained node lacks its pre-publication content");
      assert.equal(cell.writerAuthored?.outcome, "committed",
        "Transaction writer did not commit its constrained transaction");
      assert.equal(cell.writerAuthored.outboundCount, 1,
        "Transaction writer submitted another operation count");
      assert.deepEqual(cell.writerAuthored.labels,
        [`${writer}-reload-a`, `${writer}-reload-b`],
        "Transaction writer authored another pair of nodes");
      assert.equal(cell.postLoadAuthored?.author, reader,
        "Transaction reader did not author the post-load transaction");
      assert.equal(cell.postLoadAuthored.outcome, "committed",
        "Transaction reader did not commit its post-load transaction");
      assert.equal(cell.postLoadAuthored.label, `${writer}-${reader}-postload`,
        "Transaction reader authored another node");
      assert.equal(cell.postLoadAuthored.outboundCount, 1,
        "Transaction reader submitted another operation count");
      assert.equal(cell.postLoadAuthored.editsApplied, 2,
        "Transaction reader applied another edit count");
      assert.equal(cell.postLoadAuthored.nestedScopes, 1,
        "Transaction reader lacks a nested scope");
      assert.equal(cell.postLoadAuthored.sequencedCommitCount, 1,
        "The post-load transaction was not one sequenced commit");
      assert(typeof cell.postLoadAuthored.originatorId === "string"
        && cell.postLoadAuthored.originatorId.length > 0,
      "The post-load transaction lacks an originator");
      assert.equal(cell.peerObservation?.observed, true,
        "The post-load transaction lacks peer observation");
      assert.equal(cell.peerObservation.label, cell.postLoadAuthored.label,
        "The peer observed another node");
      assert(implementations.includes(cell.peerObservation.implementation),
        "The transaction peer has another implementation");
      assert.equal(cell.pendingTreeCount, 0,
        "Transaction reload left pending commits");
      assert.equal(cell.inflightSubmissionCount, 0,
        "Transaction reload left submissions in flight");
      assert(Array.isArray(cell.artifacts) && cell.artifacts.length > 0,
        "Missing transaction reload artifact");
    }
  }
  return results;
}

async function writeTransactionReloadArtifact(context, item, raw) {
  const relative = `transaction-reload/${item.writer}-${item.reader}.json`;
  const path = join(context.artifactDirectory, relative);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify({
    formatVersion: 1,
    runId: context.runId,
    profileDigest: context.profileDigest,
    kind: "transaction-reload",
    subject: `${item.writer}->${item.reader}`,
    documentId: item.documentId,
    measured: {
      writerAuthored: item.writerAuthored,
      constrainedNode: item.constrainedNode,
      postLoadAuthored: item.postLoadAuthored,
      peerObservation: item.peerObservation,
      historyVerified: item.historyVerified,
      historyEvidence: item.historyEvidence,
      nodeIdentityVerified: item.nodeIdentityVerified,
    },
    raw,
  })}\n`, { mode: 0o600 });
  return relative;
}

async function readTransactionCell(config, context, row, reader) {
  const containers = [];
  let adapter;
  let failure;
  try {
    let load;
    let rawLoad;
    let loaded;
    if (reader === "upstream") {
      const session = await openSession(config, containers, row.documentId, false,
        { cache: false, observeStorage: true, store: arrayServiceStore });
      adapter = upstreamAdapter(session);
      await adapter.awaitSynced(row.publicationSequenceNumber);
      load = storageLoad(session.storageObservations, row.version);
      rawLoad = session.storageObservations;
    } else {
      adapter = await nativeAdapter(reader, config, {
        runId: context.runId,
        documentId: row.documentId,
        tenant: config.tenantId,
        viewSchema: context.arrayViewSchema,
      }, row.jwt);
      await adapter.awaitSynced(row.publicationSequenceNumber);
      loaded = await adapter.checkpoint();
      rawLoad = adapter.evidence();
      load = loadRequests(rawLoad, row.version, row.snapshotSequenceNumber);
    }
    loaded ??= await adapter.checkpoint();
    const rightLabels = arrayFieldLabels(loaded, "right");
    const leftLabels = arrayFieldLabels(loaded, "left");
    const writerIndexes = row.writerAuthored.labels
      .map((label) => rightLabels.indexOf(label));
    assert(writerIndexes.every((index) => index >= 0)
      && writerIndexes[0] < writerIndexes[1],
    `Transaction reload lost the writer's composed commit: ${rightLabels}`);
    assert.equal(leftLabels[0], "anchor",
      `Transaction reload lost the constrained node: ${leftLabels}`);
    const commitEvidence = writerCommitEvidence(loaded, row.writerAuthored.labels);
    const historyEvidence = {
      trunkCount: loaded.history?.trunk?.length ?? null,
      pendingCount: loaded.history?.pending?.length ?? null,
      retainedCount: loaded.retained?.history?.length ?? 0,
      ...commitEvidence,
    };
    const historyVerified = Array.isArray(loaded.history?.trunk)
      && Array.isArray(loaded.history?.pending)
      && loaded.history.pending.length === 0
      && commitEvidence.composedCommitCount >= 1
      && commitEvidence.partialCommitCount === 0;
    const reloadedNode = arrayFieldElements(loaded, "left")[
      row.constrainedNode.index
    ] ?? null;
    const nodeIdentityVerified = JSON.stringify(reloadedNode)
      === JSON.stringify(row.constrainedNode.value);
    const label = `${row.writer}-${reader}-postload`;
    const baseline = loaded.sequenceNumber;
    const authoredResult = await adapter.transaction({
      constraints: [{ type: "nodeInDocument", path: ["left", "0"] }],
      edits: [
        {
          op: "array-insert",
          path: ["left"],
          index: 1,
          values: [transactionPointValue(label, 31)],
        },
        {
          op: "transaction",
          constraints: [],
          result: "commit",
          edits: [{
            op: "array-insert",
            path: ["right"],
            index: 0,
            values: [transactionPointValue(`${label}-nested`, 32)],
          }],
        },
      ],
      result: "commit",
    });
    await adapter.awaitSynced();
    const continuation = await acknowledgedSubmission(
      row.observer,
      adapter,
      baseline,
      reader,
    );
    const authored = await adapter.checkpoint();
    assert(arrayFieldLabels(authored, "left").includes(label),
      "The post-load transaction did not reach the reader's own tree");
    const peer = await openSession(config, containers, row.documentId, false,
      { cache: false, store: arrayServiceStore });
    const peerAdapter = upstreamAdapter(peer);
    await peerAdapter.awaitSynced(continuation.outerSequenceNumber);
    const peerCheckpoint = await peerAdapter.checkpoint();
    const peerLeftLabels = arrayFieldLabels(peerCheckpoint, "left");
    assert(peerLeftLabels.includes(label),
      "The post-load transaction is missing on the peer");
    assert(arrayFieldLabels(peerCheckpoint, "right").includes(`${label}-nested`),
      "The nested scope is missing on the peer");
    const commit = continuation.commits[0];
    assert(commit, "The post-load transaction lacks operation identity");
    const item = {
      runId: context.runId,
      profileDigest: context.profileDigest,
      profile: "array",
      writer: row.writer,
      reader,
      writerVersion: row.version,
      loadedVersion: load.loadedVersion,
      readerInstanceId: adapter.instanceId,
      scenarioId: "transaction-summary-postload",
      loaded: true,
      historyVerified,
      historyEvidence,
      nodeIdentityVerified,
      constrainedNode: row.constrainedNode,
      writerAuthored: row.writerAuthored,
      postLoadAuthored: {
        author: reader,
        label,
        outcome: authoredResult.outcome,
        outboundCount: authoredResult.outboundCount,
        editsApplied: authoredResult.callback.editsApplied,
        nestedScopes: authoredResult.callback.nested.length,
        commitRevision: authoredResult.commitRevision,
        originatorId: commit.originatorId,
        sequencedCommitCount: continuation.commits.length,
      },
      peerObservation: {
        implementation: "upstream",
        label,
        observed: peerLeftLabels.includes(label),
      },
      pendingTreeCount: authored.pendingTreeCount,
      inflightSubmissionCount: authored.inflightSubmissionCount,
      documentId: row.documentId,
      artifacts: [],
    };
    item.artifacts = [await writeTransactionReloadArtifact(context, item, {
      load: rawLoad,
      restoredHistory: {
        history: loaded.history ?? null,
        retained: loaded.retained ?? null,
      },
      reloadedConstrainedNode: reloadedNode,
      authoredResult,
      continuation,
      peer: peerCheckpoint,
      history: await serverHistory(row.observer),
    })];
    return item;
  } catch (error) {
    failure = error;
    throw error;
  } finally {
    const cleanup = [];
    if (adapter && reader !== "upstream") cleanup.push(() => adapter.close());
    for (const container of containers.toReversed()) {
      if (!container.closed) cleanup.push(() => container.dispose());
    }
    await cleanupAll(failure, `${reader} transaction reload cleanup failed`, cleanup);
  }
}

async function runTransactionWriterRow(config, context, writer) {
  const containers = [];
  const natives = [];
  let failure;
  try {
    const creator = await openSession(config, containers, undefined, false,
      { store: arrayServiceStore });
    const documentId = creator.container.resolvedUrl.id;
    await publishUpstreamSummary(config, containers, documentId,
      `Transaction ${writer} bootstrap`, { store: arrayServiceStore });
    const upstreamSession = await openSession(config, containers, documentId,
      false, { store: arrayServiceStore });
    const upstream = upstreamAdapter(upstreamSession);
    const { jwt } = await tokenProvider(config)
      .fetchOrdererToken(config.tenantId, documentId);
    for (const target of nativeTargets) {
      natives.push(await nativeAdapter(target, config, {
        runId: context.runId,
        documentId,
        tenant: config.tenantId,
        viewSchema: context.arrayViewSchema,
      }, jwt));
    }
    const adapters = { upstream, javascript: natives[0], erlang: natives[1] };
    await settle(adapters);
    await adapters[writer].arrayInsert(["left"], 0, [
      transactionPointValue("anchor", 0),
    ]);
    const anchored = await settle(adapters);
    const anchorObservation = anchored.observations
      .find(({ implementation }) => implementation === writer);
    assert(anchorObservation, `Missing the ${writer} anchor observation`);
    const constrainedNode = {
      field: "left",
      index: 0,
      label: "anchor",
      value: arrayFieldElements(anchorObservation, "left")[0] ?? null,
    };
    assert(constrainedNode.value !== null,
      "The constrained node is missing before publication");
    const labels = [`${writer}-reload-a`, `${writer}-reload-b`];
    const writerResult = await adapters[writer].transaction({
      constraints: [{ type: "nodeInDocument", path: ["left", "0"] }],
      edits: [
        {
          op: "array-insert",
          path: ["right"],
          index: 0,
          values: [transactionPointValue(labels[0], 41)],
        },
        {
          op: "transaction",
          constraints: [],
          result: "commit",
          edits: [{
            op: "array-insert",
            path: ["right"],
            index: 1,
            values: [transactionPointValue(labels[1], 42)],
          }],
        },
      ],
      result: "commit",
    });
    await settle(adapters);
    const publication = await publishWriterSummary(
      config,
      containers,
      creator,
      documentId,
      jwt,
      writer,
      adapters,
      {
        store: arrayServiceStore,
        tailEdit: (adapter, value) =>
          adapter.arrayInsert(["narrow"], 0, [transactionPointValue(value, 99)]),
      },
    );
    const row = {
      writer,
      documentId,
      jwt,
      observer: creator,
      constrainedNode,
      writerAuthored: {
        labels,
        outcome: writerResult.outcome,
        outboundCount: writerResult.outboundCount,
        commitRevision: writerResult.commitRevision,
        editsApplied: writerResult.callback.editsApplied,
        nestedScopes: writerResult.callback.nested.length,
      },
      ...publication,
    };
    for (const native of natives.toReversed()) await native.close();
    natives.length = 0;
    if (!upstream.session.container.closed) upstream.session.container.dispose();
    const results = {};
    for (const reader of implementations) {
      results[reader] = await readTransactionCell(config, context, row, reader);
    }
    return results;
  } catch (error) {
    failure = error;
    throw error;
  } finally {
    const cleanupErrors = [];
    for (const native of natives.toReversed()) {
      try {
        await native.close();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    for (const container of containers.toReversed()) {
      try {
        if (!container.closed) container.dispose();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    if (cleanupErrors.length > 0) {
      if (failure) failure.cleanupErrors = cleanupErrors;
      else {
        throw new AggregateError(cleanupErrors,
          `Cleanup failed for ${writer} transaction reload row`);
      }
    }
  }
}

export async function runTransactionReloadMatrix(config, context, {
  runRow = runTransactionWriterRow,
} = {}) {
  assert(typeof context?.runId === "string" && context.runId.length > 0,
    "runTransactionReloadMatrix context requires runId");
  assert.match(context.profileDigest ?? "", /^[0-9a-f]{64}$/,
    "runTransactionReloadMatrix context requires profileDigest");
  assert(typeof context.arrayViewSchema === "string"
    && context.arrayViewSchema.length > 0,
  "runTransactionReloadMatrix context requires arrayViewSchema");
  assert(typeof context.artifactDirectory === "string"
    && context.artifactDirectory.length > 0,
  "runTransactionReloadMatrix context requires artifactDirectory");
  const results = {};
  for (const writer of implementations) {
    results[writer] = await runRow(config, context, writer);
  }
  return validateTransactionReloadResults(results);
}

async function openUndoRedoReader(
  config,
  context,
  containers,
  documentId,
  jwt,
  reader,
) {
  if (reader === "upstream") {
    const session = await openSession(config, containers, documentId, false, {
      cache: false,
      observeStorage: true,
    });
    return {
      adapter: upstreamAdapter(session),
      loadEvidence(version) {
        return storageLoad(session.storageObservations, version);
      },
      boundaryStorageResponses() {
        return structuredClone(session.storageObservations);
      },
      close() {
        if (!session.container.closed) session.container.dispose();
      },
    };
  }
  const adapter = await nativeAdapter(reader, config, {
    runId: context.runId,
    documentId,
    tenant: config.tenantId,
    viewSchema: context.viewSchema,
  }, jwt);
  return {
    adapter,
    loadEvidence(version) {
      return loadRequests(adapter.evidence(), version);
    },
    boundaryStorageResponses() {
      return structuredClone(adapter.evidence().http);
    },
    close: () => adapter.close(),
  };
}

async function publishUndoRedoSummary(
  config,
  containers,
  documentId,
  writer,
  adapter,
  stage,
  jwt,
) {
  if (writer === "upstream") {
    const publication = await publishUpstreamSummary(
        config,
        containers,
        documentId,
        `Task 8 ${writer} ${stage}`,
      );
    return {
      version: publication.summaryAckOp.contents.handle,
      snapshotSequenceNumber: publication.summaryReferenceSequenceNumber,
      rawPublicationIdentity: {
        version: publication.summaryAckOp.contents.handle,
        snapshotSequenceNumber: publication.summaryReferenceSequenceNumber,
        sequenceNumber: publication.summaryAckOp.sequenceNumber,
      },
    };
  }
  const publication = await adapter.summarizePublication();
  const version = publication.version;
  const observedSequenceNumber = publication.snapshotSequenceNumber;
  const storedSequenceNumber =
    await publishedSequence(config, documentId, jwt, version);
  assert.equal(observedSequenceNumber, storedSequenceNumber,
    `${writer} summary response differs from stored publication`);
  return {
    version,
    snapshotSequenceNumber: observedSequenceNumber,
    rawPublicationIdentity: publication,
  };
}

async function writeUndoRedoReloadArtifact(context, item, raw) {
  const relative =
    `undo-redo-reload/${item.writer}-${item.stage}-${item.reader}.json`;
  const path = join(context.artifactDirectory, relative);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `${JSON.stringify({
    formatVersion: 1,
    runId: context.runId,
    profileDigest: context.profileDigest,
    kind: "undo-redo-reload",
    subject: `${item.writer}:${item.stage}->${item.reader}`,
    documentId: item.documentId,
    measured: Object.fromEntries(Object.entries(item)
      .filter(([name]) => name !== "artifacts")),
    raw,
  })}\n`, { mode: 0o600 });
  return relative;
}

function checkpointRevisionEvidence(checkpoint) {
  return [...new Set((checkpoint.history?.trunk ?? []).flatMap((entry) => {
    const revision = entry.commit?.revision ?? entry.revision;
    return revision === undefined ? [] : [String(revision)];
  }))].map((revision) => ({ revision }));
}

async function runUndoRedoReloadReader(
  config,
  context,
  environment,
  writer,
  reader,
  stage,
  version,
  snapshotSequenceNumber,
  expectedTree,
) {
  const fresh = await openUndoRedoReader(
    config,
    context,
    environment.containers,
    environment.documentId,
    environment.jwt,
    reader,
  );
  let failure;
  const trace = [];
  const handleNames = [];
  try {
    await fresh.adapter.awaitSynced();
    const loaded = await fresh.adapter.checkpoint();
    trace.push({ label: "loaded", observation: loaded });
    const load = fresh.loadEvidence(version);
    const boundaryStorageResponses = fresh.boundaryStorageResponses();
    const consumedSnapshotSequenceNumber = load.snapshotSequenceNumber;
    assert.deepEqual(loaded.wholeTree, expectedTree,
      `${writer} ${stage}->${reader} loaded another tree`);
    let historicalRetainError;
    try {
      await fresh.adapter.retainLastLocalCommit("historical");
    } catch (error) {
      const message = error?.cause?.message ?? error?.message ?? String(error);
      assert.match(message, /No unretained local commit is available/,
        `${writer} ${stage}->${reader} returned another pre-edit retain error`);
      historicalRetainError = message;
    }
    assert(historicalRetainError,
      `${writer} ${stage}->${reader} recreated a historical handle`);
    assert.equal(
      (loaded.commits ?? []).some(
        ({ type, local, factoryAvailable }) =>
          type === "commit" && (local === true || factoryAvailable === true),
      ),
      false,
      `${writer} ${stage}->${reader} loaded a historical local commit factory`,
    );
    await fresh.adapter.set(["note"], `${writer}-${stage}-${reader}`);
    const retained = await fresh.adapter.retainLastLocalCommit("post-load");
    handleNames.push("post-load");
    const undo = await fresh.adapter.revert("post-load", true);
    const postUndoStatus = await fresh.adapter.revertibleStatus("post-load");
    await fresh.adapter.awaitSynced();
    const final = await fresh.adapter.checkpoint();
    trace.push({ label: "final", observation: final });
    const commits = [...(loaded.commits ?? []), ...(final.commits ?? [])];
    const settlement = commits.findLast(
      ({ type, kind }) => type === "settlement" && kind === "Undo",
    )?.outcome;
    const item = {
      writer,
      reader,
      stage,
      runId: context.runId,
      profileDigest: context.profileDigest,
      documentId: environment.documentId,
      writerVersion: version,
      loadedVersion: version,
      snapshotSequenceNumber,
      publicationReferenceSequenceNumber: snapshotSequenceNumber,
      consumedSnapshotSequenceNumber,
      replayStartSequenceNumber: load.replayStartSequenceNumber,
      selectedSummaryRequests: load.selectedSummaryRequests,
      loadEvidence: load,
      loaded: true,
      historicalHandleAvailable: false,
      historicalRetainError,
      historicalLoadCommits: loaded.commits ?? [],
      loadedTree: loaded.wholeTree,
      expectedPublishedTree: expectedTree,
      newLocalKind: retained.kind,
      newFactoryAvailable: retained.factoryAvailable,
      newHandleStatus: retained.status,
      postUndoHandleStatus: postUndoStatus.status,
      undoKind: undo.authoredKind,
      settlement,
      authoredCount: undo.authoredCount,
      outboundCount: undo.outboundCount,
      finalTree: final.wholeTree,
      passed: true,
      failed: false,
      skipped: false,
      error: null,
      artifacts: [],
    };
    assert.deepEqual(final.wholeTree, expectedTree,
      `${writer} ${stage}->${reader} did not undo its post-load edit`);
    const acceptedHistory = await serverHistory(environment.creator);
    item.artifacts = [await writeUndoRedoReloadArtifact(context, item, {
      publication: {
        ...environment.publication.rawPublicationIdentity,
        referenceSequenceNumber: snapshotSequenceNumber,
        checkpoint: environment.publication.checkpoint,
      },
      loaded: {
        ...loaded,
        rawLoadIdentity: load.rawLoadIdentity,
      },
      final,
      retained,
      lifecycle: {
        ...undo,
        settlement,
      },
      postUndoStatus,
      load,
      boundaryStorageResponses,
      storageResponses: load.storageResponses,
      sequencedHistory: checkpointRevisionEvidence(final),
      acceptedOperationPayloads: acceptedHistory,
      initialCompressorState: environment.creator.initialCompressorState,
      acceptedOperations: acceptedTreeOperations(acceptedHistory),
      handleNames: ["post-load"],
      commitKinds: commits.filter(({ type }) => type === "commit")
        .map(({ kind }) => kind),
      settlementOutcomes: commits.filter(({ type }) => type === "settlement")
        .map(({ outcome }) => outcome),
    })];
    return item;
  } catch (error) {
    failure = error;
    if (error.checkpoint) {
      trace.push({ label: "primary-checkpoint", observation: error.checkpoint });
    }
    const drained = await captureFailureCheckpoint(
      "failure-drain",
      "intermediate",
      { [reader]: fresh.adapter },
    );
    preserveFailureCheckpoints(error, drained.checkpoint);
    trace.push(...drained.checkpoint.observations.map((observation) => ({
      label: "failure-drain",
      observation,
    })));
    error.drainErrors = drained.errors;
    const relative =
      `undo-redo-reload-failure/${writer}-${stage}-${reader}.json`;
    const path = join(context.artifactDirectory, relative);
    try {
      await mkdir(dirname(path), { recursive: true });
      await writeFile(path, `${JSON.stringify({
        formatVersion: 1,
        kind: "undo-redo-reload-failure",
        runId: context.runId,
        profileDigest: context.profileDigest,
        subject: `${writer}:${stage}->${reader}`,
        documentId: environment.documentId,
        writer,
        reader,
        stage,
        writerVersion: version,
        snapshotSequenceNumber,
        handleNames,
        commitKinds: trace.flatMap(({ observation }) =>
          (observation.commits ?? [])
            .filter(({ type }) => type === "commit")
            .map(({ kind }) => kind)),
        settlements: trace.flatMap(({ observation }) =>
          (observation.commits ?? [])
            .filter(({ type }) => type === "settlement")
            .map(({ outcome }) => outcome)),
        eventTrace: trace,
        primaryCheckpoint: error.primaryCheckpoint,
        drainCheckpoint: error.drainCheckpoint,
        error: {
          name: error?.name ?? "Error",
          message: error?.message ?? String(error),
          ...(error?.cause === undefined ? {} : { cause: error.cause }),
        },
      })}\n`, { mode: 0o600 });
      error.failurePath = path;
    } catch (captureError) {
      error.artifactCaptureError = captureError;
    }
    throw error;
  } finally {
    try {
      await fresh.close();
    } catch (error) {
      if (failure) failure.cleanupErrors = [...(failure.cleanupErrors ?? []), error];
      else throw error;
    }
  }
}

async function runUndoRedoReloadWriter(config, context, writer) {
  const containers = [];
  const natives = [];
  let failure;
  let adapters;
  let documentId;
  try {
    const creator = await openSession(config, containers);
    documentId = creator.container.resolvedUrl.id;
    await publishUpstreamSummary(
      config,
      containers,
      documentId,
      `Task 8 ${writer} reload bootstrap`,
    );
    const upstream = upstreamAdapter(await openSession(
      config,
      containers,
      documentId,
    ));
    const { jwt } = await tokenProvider(config)
      .fetchOrdererToken(config.tenantId, documentId);
    for (const target of nativeTargets) {
      natives.push(await nativeAdapter(target, config, {
        runId: context.runId,
        documentId,
        tenant: config.tenantId,
        viewSchema: context.viewSchema,
      }, jwt));
    }
    adapters = { upstream, javascript: natives[0], erlang: natives[1] };
    const environment = {
      containers,
      creator,
      documentId,
      jwt,
      publication: null,
    };
    await settle(adapters);
    await adapters[writer].set(["title"], `${writer}-undo-redo`);
    await adapters[writer].retainLastLocalCommit("edit");
    await settle(adapters);
    await adapters[writer].revert("edit", true);
    await adapters[writer].retainLastLocalCommit("undo");
    const undone = await settle(adapters);
    const undoTree = undone.observations[0].wholeTree;
    const undoPublication = await publishUndoRedoSummary(
      config,
      containers,
      documentId,
      writer,
      adapters[writer],
      "undo",
      jwt,
    );
    environment.publication = undoPublication;
    environment.publication.checkpoint =
      structuredClone(undone.observations.find(
        ({ implementation }) => implementation === writer,
      ));
    const row = { undo: {}, redo: {} };
    for (const reader of implementations) {
      row.undo[reader] = await runUndoRedoReloadReader(
        config,
        context,
        environment,
        writer,
        reader,
        "undo",
        undoPublication.version,
        undoPublication.snapshotSequenceNumber,
        undoTree,
      );
    }
    await adapters[writer].revert("undo", true);
    const redone = await settle(adapters);
    const redoTree = redone.observations[0].wholeTree;
    const redoPublication = await publishUndoRedoSummary(
      config,
      containers,
      documentId,
      writer,
      adapters[writer],
      "redo",
      jwt,
    );
    environment.publication = redoPublication;
    environment.publication.checkpoint =
      structuredClone(redone.observations.find(
        ({ implementation }) => implementation === writer,
      ));
    for (const reader of implementations) {
      row.redo[reader] = await runUndoRedoReloadReader(
        config,
        context,
        environment,
        writer,
        reader,
        "redo",
        redoPublication.version,
        redoPublication.snapshotSequenceNumber,
        redoTree,
      );
    }
    return row;
  } catch (error) {
    failure = error;
    if (error.checkpoint) error.writerCheckpoint = error.checkpoint;
    if (adapters) {
      const drained = await captureFailureCheckpoint(
        "undo-redo-reload-writer-failure-drain",
        "intermediate",
        adapters,
      );
      preserveFailureCheckpoints(error, drained.checkpoint);
      error.drainErrors = drained.errors;
      const relative = `undo-redo-reload-writer-failure/${writer}.json`;
      const path = join(context.artifactDirectory, relative);
      try {
        await mkdir(dirname(path), { recursive: true });
        await writeFile(path, `${JSON.stringify({
          formatVersion: 1,
          kind: "undo-redo-reload-writer-failure",
          runId: context.runId,
          profileDigest: context.profileDigest,
          subject: writer,
          documentId,
          writer,
          primaryCheckpoint: error.primaryCheckpoint,
          drainCheckpoint: error.drainCheckpoint,
          error: {
            name: error?.name ?? "Error",
            message: error?.message ?? String(error),
          },
        })}\n`, { mode: 0o600 });
        error.failurePath = path;
      } catch (captureError) {
        error.artifactCaptureError = captureError;
      }
    }
    throw error;
  } finally {
    const cleanupErrors = [];
    for (const native of natives.toReversed()) {
      try {
        await native.close();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    for (const container of containers.toReversed()) {
      try {
        if (!container.closed) container.dispose();
      } catch (error) {
        cleanupErrors.push(error);
      }
    }
    if (cleanupErrors.length > 0) {
      if (failure) {
        failure.cleanupErrors = [
          ...(failure.cleanupErrors ?? []),
          ...cleanupErrors,
        ];
      }
      else throw new AggregateError(cleanupErrors, "Undo/redo reload cleanup failed");
    }
  }
}

export async function runUndoRedoReloadMatrix(config, context, {
  runRow = runUndoRedoReloadWriter,
} = {}) {
  assert(typeof context?.runId === "string" && context.runId.length > 0,
    "runUndoRedoReloadMatrix context requires runId");
  assert.match(context.profileDigest ?? "", /^[0-9a-f]{64}$/,
    "runUndoRedoReloadMatrix context requires profileDigest");
  assert(typeof context.viewSchema === "string" && context.viewSchema.length > 0,
    "runUndoRedoReloadMatrix context requires viewSchema");
  const matrix = {};
  for (const writer of implementations) {
    matrix[writer] = await runRow(config, context, writer);
  }
  return matrix;
}

export async function runIdentifierReloadMatrix(config, context, {
  runRow = runIdentifierWriterRow,
} = {}) {
  assert(typeof context?.runId === "string" && context.runId.length > 0,
    "runIdentifierReloadMatrix context requires runId");
  assert.match(context.profileDigest ?? "", /^[0-9a-f]{64}$/,
    "runIdentifierReloadMatrix context requires profileDigest");
  assert(typeof context.identifierViewSchema === "string"
    && context.identifierViewSchema.length > 0,
  "runIdentifierReloadMatrix context requires identifierViewSchema");
  assert(typeof context.artifactDirectory === "string"
    && context.artifactDirectory.length > 0,
  "runIdentifierReloadMatrix context requires artifactDirectory");
  const results = {};
  for (const writer of implementations) {
    results[writer] = await runRow(config, context, writer);
  }
  return validateIdentifierReloadResults(results);
}

export async function runService(config) {
  if (!existsSync(join(directory, ".output/source/source-smoke.json"))) {
    await captureSource(join(directory, ".output/source"));
  }
  const { capture } = await preflight(config);
  const document = capture.documentId;
  const { jwt } = await tokenProvider(config).fetchOrdererToken(config.tenantId, document);
  const versions = { upstream: capture.summaryVersion };
  const snapshotPositions = { upstream: capture.summaryReferenceSequenceNumber };
  const publicationPositions = {
    upstream: capture.summaryAcknowledgement.sequenceNumber,
  };
  assert(Number.isSafeInteger(snapshotPositions.upstream)
    && Number.isSafeInteger(publicationPositions.upstream)
    && publicationPositions.upstream >= snapshotPositions.upstream,
  "Upstream capture omitted snapshot/publication positions");
  const results = [];
  let title = "real-service";
  for (const writer of ["upstream", "javascript", "erlang"]) {
    if (writer !== "upstream") {
      title = `${writer}-writer`;
      const version = writer === "javascript"
        ? await editJavascript(config, document, jwt, title, true)
        : await editErlang(config, document, jwt, title, true);
      assert(typeof version === "string" && version.length > 0,
        `${writer} returned no published version`);
      versions[writer] = version;
      assert.equal(await publishedVersion(config, document, jwt), version);
      await observeFreshUpstream(config, document, title);
      const snapshot = await publishedSequence(config, document, jwt, version);
      snapshotPositions[writer] = snapshot;
      publicationPositions[writer] =
        await publicationSequence(config, document, jwt, version, snapshot);
    }
    for (const reader of ["upstream", "javascript", "erlang"]) {
      const next = `${writer}-${reader}-continued`;
      if (reader === "upstream") {
        await reloadAndEdit(config, document, title, next);
      } else {
        const edited = reader === "javascript"
          ? await editJavascript(config, document, jwt, next, false)
          : await editErlang(config, document, jwt, next, false);
        assert.equal(edited, next, `${reader} did not confirm its edit`);
        await observeFreshUpstream(config, document, next);
      }
      assert.equal(await publishedVersion(config, document, jwt), versions[writer],
        "Reader unexpectedly replaced the writer's checkpoint");
      results.push({
        writer, reader, writerVersion: versions[writer],
        snapshotSequenceNumber: snapshotPositions[writer],
        publicationSequenceNumber: publicationPositions[writer],
        scenarioId: "floodgate-summary-tail",
        loaded: true, continuedEditing: true, peerObservedEdit: true,
      });
      title = next;
    }
  }
  const repeatedTitle = "repeated-javascript-writer";
  const repeatedVersion = await editJavascript(config, document, jwt, repeatedTitle, true);
  assert.notEqual(repeatedVersion, versions.javascript, "Repeated publication kept the old head");
  assert.equal(await publishedVersion(config, document, jwt), repeatedVersion);
  const repeatedSnapshot =
    await publishedSequence(config, document, jwt, repeatedVersion);
  const repeatedAck = await publicationSequence(
    config, document, jwt, repeatedVersion, repeatedSnapshot,
  );
  await observeFreshUpstream(config, document, repeatedTitle);
  assert.equal(await editErlang(config, document, jwt,
    "after-repeated-publication", false), "after-repeated-publication");
  await observeFreshUpstream(config, document, "after-repeated-publication");
  assert.equal(await publishedVersion(config, document, jwt), repeatedVersion);
  assert.equal(await editErlang(config, document, jwt,
    "after-auto-policy", false, true), "after-auto-policy");
  assert.equal(await publishedVersion(config, document, jwt), repeatedVersion,
    "BEAM automatically published a loaded SharedTree");
  await observeFreshUpstream(config, document, "after-auto-policy");
  return {
    document,
    versions,
    results: validateFocusedResults(results),
    repeatedPublication: {
      version: repeatedVersion,
      snapshotSequenceNumber: repeatedSnapshot,
      publicationSequenceNumber: repeatedAck,
      upstreamAndErlangContinued: true,
    },
    loadedTreeAutomaticSummaryDisabled: true,
  };
}

async function main() {
  const { values } = parseArgs({
    options: {
      service: { type: "string" },
      local: { type: "boolean", default: false },
    },
  });
  assert(!values.local || values.service === "floodgate",
    "--local requires --service floodgate");
  assert(!values.service || values.service === "floodgate",
    "Unsupported summary interop service");
  const result = values.service
    ? values.local ? await withLocalFloodgate(runService) : await runService(serviceConfig())
    : await runArtifactInterop();
  console.log(JSON.stringify(result));
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
