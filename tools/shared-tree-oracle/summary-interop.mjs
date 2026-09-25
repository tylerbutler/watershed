import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { randomUUID } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { fileURLToPath, pathToFileURL } from "node:url";
import { parseArgs, promisify } from "node:util";
import { SummaryType } from "@fluidframework/driver-definitions/internal";

import { DeliveryGate } from "./delivery-gate.mjs";
import { Point } from "./schema.mjs";
import {
  canonicalValue,
  decodeTreeSubmissions,
  nativeAdapter,
  publishUpstreamSummary,
  refresherValues,
  rootValue,
  serverHistory,
  settle,
  success,
  until,
  upstreamAdapter,
} from "./interop-scenarios.mjs";
import {
  openSession, preflight, serviceConfig, tokenProvider, withLocalFloodgate,
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

export function loadRequests(evidence, version, snapshotSequenceNumber) {
  assert(Number.isSafeInteger(snapshotSequenceNumber) && snapshotSequenceNumber >= 0,
    "Native reader lacks a selected-summary sequence");
  const successful = evidence.http.filter(({ status }) => status >= 200 && status < 300);
  const selectedSummaryRequests = [...new Set(successful.flatMap(({ path }) => {
    const match = path.match(/\/git\/commits\/([^/?]+)/);
    return match ? [decodeURIComponent(match[1])] : [];
  }))];
  assert(selectedSummaryRequests.includes(version),
    "Native reader did not request the selected summary commit");
  assert(successful.some(({ path }) => path.includes("/git/trees/")),
    "Native reader did not request the selected summary trees");
  assert(successful.some(({ path }) => path.includes("/git/blobs/")),
    "Native reader did not request the selected summary blobs");
  const deliveredSequences = evidence.delivered
    .filter(({ direction, kind }) => direction === "inbound" && kind === "op")
    .flatMap(({ sequenceNumbers }) => sequenceNumbers)
    .filter(Number.isSafeInteger);
  const handshakeStarts = (evidence.handshakes ?? []).flatMap((handshake) => {
    const initial = handshake.initialMessageSequenceNumbers
      ?.filter(Number.isSafeInteger) ?? [];
    const applied = initial.filter((sequenceNumber) =>
      sequenceNumber > snapshotSequenceNumber);
    if (applied.length > 0) return [Math.min(...applied) - 1];
    return [];
  });
  const deliveryStarts = deliveredSequences.length > 0
    ? [Math.min(...deliveredSequences) - 1]
    : [];
  const measuredStarts = deliveryStarts.length > 0 ? deliveryStarts : handshakeStarts;
  assert(measuredStarts.length > 0, "Native reader lacks measured replay evidence");
  return {
    loadedVersion: version,
    selectedSummaryRequests,
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

function storageLoad(observations, version) {
  const selectedSummaryRequests = [...new Set(observations.flatMap((observation) =>
    observation.operation === "getVersions"
      ? observation.versions.map(({ id }) => id)
      : []))];
  assert(selectedSummaryRequests.includes(version),
    "Upstream reader did not select the published summary version");
  assert(observations.some(({ operation }) => operation === "getSnapshotTree"),
    "Upstream reader did not request the selected snapshot");
  assert(observations.some(({ operation }) => operation === "readBlob"),
    "Upstream reader did not read the selected summary hierarchy");
  const replayStarts = observations.flatMap(({ operation, from }) =>
    operation === "fetchMessages" && Number.isSafeInteger(from) ? [from] : []);
  assert(replayStarts.length > 0, "Upstream reader lacks measured delta replay");
  return {
    loadedVersion: version,
    selectedSummaryRequests,
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
) {
  const tailAuthor = writer === "javascript" ? "erlang" : "javascript";
  const tailBaseline = await adapters[tailAuthor].checkpoint();
  let version;
  let snapshotSequenceNumber;
  let dataEdit;
  if (writer === "upstream") {
    const summarizer = await openSession(config, containers, documentId, true);
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
    await adapters[tailAuthor].set(["note"], `between-${writer}-${randomUUID()}`);
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
    await adapters[tailAuthor].set(["note"], `between-${writer}-${randomUUID()}`);
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
    const loaded = await adapter.checkpoint();
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
