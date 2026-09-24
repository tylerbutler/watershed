import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { randomUUID } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { fileURLToPath, pathToFileURL } from "node:url";
import { parseArgs, promisify } from "node:util";
import { SummaryType } from "@fluidframework/driver-definitions/internal";

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
  function child(name, type) {
    const entry = tree.tree.find((value) => value.path === name);
    assert(entry && entry.type === type, `Published summary lacks ${name} ${type}`);
    return entry.sha;
  }
  tree = await object(`${base}/trees/${child(".app", "tree")}`);
  tree = await object(`${base}/trees/${child(".protocol", "tree")}`);
  const blob = await object(`${base}/blobs/${child("attributes", "blob")}`);
  assert.equal(blob.encoding, "base64", "Protocol attributes use a different encoding");
  const attributes = JSON.parse(Buffer.from(blob.content, "base64").toString("utf8"));
  assert(Number.isSafeInteger(attributes.sequenceNumber)
    && attributes.sequenceNumber > 0, "Published snapshot has no sequence number");
  return attributes.sequenceNumber;
}

async function publicationSequence(config, document, jwt, version, snapshot) {
  const url = `${config.httpUrl}/deltas/${config.tenantId}/${document}`
    + `?from=${snapshot}&to=${snapshot + 200}`;
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${jwt}` },
  });
  assert.equal(response.status, 200, "Cannot read publication delta history");
  const { value: messages } = await response.json();
  assert(Array.isArray(messages), "Invalid publication delta history");
  for (const [index, message] of messages.entries()) {
    assert.equal(message.sequenceNumber, snapshot + index + 1,
      "Publication prefix has a gap or duplicate");
  }
  const ack = messages.find((message) => message.type === "summaryAck"
    && (typeof message.contents === "string"
      ? JSON.parse(message.contents) : message.contents)?.handle === version);
  assert(Number.isSafeInteger(ack?.sequenceNumber)
    && ack.sequenceNumber > snapshot, "No acknowledgement for the published checkpoint");
  return ack.sequenceNumber;
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
  } finally {
    for (const container of containers) container.dispose();
  }
}

async function observeFreshUpstream(config, document, expectedTitle) {
  const containers = [];
  try {
    const peer = await within(openSession(config, containers, document),
      "independent upstream peer");
    assert.equal(peer.data.view.root.title, expectedTitle);
    return true;
  } finally {
    for (const container of containers) container.dispose();
  }
}

export function validateResults(results) {
  const implementations = ["upstream", "javascript", "erlang"];
  const requiredPairs = implementations.flatMap((writer) =>
    implementations.map((reader) => `${writer}->${reader}`));
  assert(Array.isArray(results) && results.length === requiredPairs.length,
    "Summary interop needs exactly nine persistence cells");
  for (const cell of results) {
    assert(implementations.includes(cell.writer), "Invalid writer identity");
    assert(implementations.includes(cell.reader), "Invalid reader identity");
    assert(typeof cell.writerVersion === "string" && cell.writerVersion.length > 0,
      "Missing published writer version");
    assert(Number.isSafeInteger(cell.snapshotSequenceNumber)
      && cell.snapshotSequenceNumber >= 0
      && Number.isSafeInteger(cell.publicationSequenceNumber)
      && cell.publicationSequenceNumber >= cell.snapshotSequenceNumber,
    "Invalid snapshot/publication positions");
    assert(typeof cell.scenarioId === "string" && cell.scenarioId.length > 0,
      "Missing persistence scenario");
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
  } finally {
    await environment.close();
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
    } finally {
      for (const session of sessions) environment.dispose(session);
    }
  }
  return results;
}

export async function runArtifactInterop({
  produce = produceSummary, cases = persistenceStates,
} = {}) {
  const owned = await mkdtemp(join(tmpdir(), "watershed-summary-interop-"));
  const input = join(repository, "test/fixtures/shared_tree/cases/summary-writer-matrix.json");
  try {
    const results = [];
    const retained = [];
    const environment = makeEnvironment();
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
    } finally {
      await environment.close();
    }
    const splitMap = await checkSplitMap(owned);
    return { reference: identity, targets: results, retained, splitMap };
  } finally {
    await rm(owned, { recursive: true, force: true });
  }
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
    results: validateResults(results),
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
