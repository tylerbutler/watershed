import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { promisify } from "node:util";
import {
  captureContainers,
  validateContainerSnapshotProfile,
} from "./container-corpus.mjs";
import { validateRuntimeCase } from "./generate.mjs";

const execute = promisify(execFile);
const expectedCases = [
  ["bootstrap-map-handles", "container"],
  ["batched-commits", "runtime"],
  ["reconnect-before-ack", "history"],
  ["summary-tail", "summary"],
  ["summary-writer-matrix", "summary"],
  ["container-foundations", "container"],
  ["summary-foundations", "summary"],
];

async function capture(directory) {
  await captureContainers(directory);
  return JSON.parse(await readFile(join(directory, "container-cases.json"), "utf8"));
}

function assertSnapshot(snapshot) {
  assert.equal(snapshot.blobEncoding, "base64");
  assert(Object.keys(snapshot.blobs).length > 0);
  assert(Object.keys(snapshot.tree.trees).length > 0);
}

function assertSerializedPendingState(state) {
  assert.equal(state.encoding, "utf8");
  assert.equal(typeof state.content, "string");
  assert(state.content.length > 0);
  const parsed = JSON.parse(state.content);
  assert.equal(parsed.attached, true);
  assert(Object.keys(parsed.pendingRuntimeState).length > 0);
  assert(Object.keys(parsed.snapshotBlobs).length > 0);
  assert(parsed.savedOps.length > 0);
  return parsed;
}

function withMetadata(snapshot, update) {
  const copy = structuredClone(snapshot);
  const id = copy.tree.blobs[".metadata"];
  const metadata = JSON.parse(Buffer.from(copy.blobs[id], "base64"));
  update(metadata);
  copy.blobs[id] = Buffer.from(JSON.stringify(metadata)).toString("base64");
  return copy;
}

test("container snapshot validation refuses runtime profile drift", async (t) => {
  const output = await mkdtemp(join(tmpdir(), "watershed-container-profile-"));
  t.after(() => rm(output, { recursive: true, force: true }));
  const [value] = await capture(output);
  const snapshot = value.raw.snapshot;
  const profile = validateContainerSnapshotProfile(snapshot);
  assert.equal(profile.metadata.documentSchema.info.minVersionForCollab, "2.117.0");
  assert.equal(profile.metadata.documentSchema.runtime.idCompressorMode, "on");
  assert.equal(profile.metadata.documentSchema.runtime.opGroupingEnabled, true);
  assert.equal(profile.schema.version, 2);
  assert(profile.schema.nodes["org.watershed.shared-tree.m1.Root"]);

  assert.throws(() => validateContainerSnapshotProfile(withMetadata(snapshot, (metadata) => {
    metadata.documentSchema.info.minVersionForCollab = "3.0.0";
  })), /minVersionForCollab/);
  assert.throws(() => validateContainerSnapshotProfile(withMetadata(snapshot, (metadata) => {
    metadata.documentSchema.runtime.idCompressorMode = "off";
  })), /idCompressorMode/);
  assert.throws(() => validateContainerSnapshotProfile(withMetadata(snapshot, (metadata) => {
    metadata.documentSchema.runtime.opGroupingEnabled = false;
  })), /opGroupingEnabled/);
  assert.throws(() => validateContainerSnapshotProfile(withMetadata(snapshot, (metadata) => {
    metadata.documentSchema.runtime.compressionLz4 = true;
  })), /compressionLz4/);
  assert.throws(() => validateContainerSnapshotProfile(withMetadata(snapshot, (metadata) => {
    metadata.summaryFormatVersion = 2;
  })), /summaryFormatVersion/);
  assert.throws(() => validateContainerSnapshotProfile(withMetadata(snapshot, (metadata) => {
    metadata.gcFeature = 4;
  })), /gcFeature/);
  const withoutCompressor = structuredClone(snapshot);
  delete withoutCompressor.tree.blobs[".idCompressor"];
  assert.throws(() => validateContainerSnapshotProfile(withoutCompressor), /.idCompressor/);
});

test("runtime cases include replay prefixes and genuinely pending local edits", async (t) => {
  const output = await mkdtemp(join(tmpdir(), "watershed-runtime-input-"));
  t.after(() => rm(output, { recursive: true, force: true }));
  const [bootstrap, batch] = await capture(output);
  for (const value of [bootstrap, batch]) {
    assert(Array.isArray(value.input.decoderInput.deliveryPrefix), "missing runtime delivery prefix");
    assert.deepEqual(
      value.input.decoderInput.deliveryPrefix.map(({ sequenceNumber }) => sequenceNumber),
      [1, 2],
    );
    assert(value.input.decoderInput.deliveryPrefix.every(({ type }) => type === "join"));
  }
  assert.deepEqual(batch.input.localEdits, [
    { path: ["title"], value: { kind: "string", value: "batched" } },
    { path: ["enabled"], value: { kind: "boolean", value: true } },
    { path: ["rating"], value: { kind: "number", value: 3 } },
  ]);
  assert.equal(batch.expected.observations[0].checkpoint, "local-after-batch");
  assert.equal(batch.expected.observations[0].pendingCount, 3);
  assert.equal(batch.expected.observations[1].pendingCount, 0);
  assert.equal(batch.input.writer.clientId, batch.input.decoderInput.groupedWireMessages[0].clientId);
  assert.equal(typeof batch.input.writer.compressor, "string");
  assert.deepEqual(bootstrap.expected.observations.slice(1, 3).map(({ rejection }) => rejection),
    ["missing-tree-handle", "wrong-tree-handle-kind"]);
  assert.equal(bootstrap.expected.observations[3].handleResolvedToTree, true);
  for (const value of [bootstrap, batch]) {
    assert(value.expected.observations.every(({ root, pendingCount, treePositions, invalidated }) =>
      root && Number.isInteger(pendingCount) && Array.isArray(treePositions)
      && typeof invalidated === "boolean"), `${value.id}: incomplete runtime projection`);
  }
  assert.match(bootstrap.raw.bootstrapRejections.missing, /Bootstrap tree handle is missing/);
  assert.match(bootstrap.raw.bootstrapRejections.wrongKind, /Bootstrap handle is not a tree/);
  for (const value of [bootstrap, batch]) {
    assert.doesNotThrow(() => validateRuntimeCase(value));
    for (const mutate of [
      (copy) => { delete copy.input.decoderInput.deliveryPrefix; },
      (copy) => { copy.input.decoderInput.deliveryPrefix.shift(); },
      (copy) => { copy.input.decoderInput.deliveryPrefix.pop(); },
      (copy) => { copy.input.decoderInput.deliveryPrefix.reverse(); },
    ]) {
      const copy = structuredClone(value);
      mutate(copy);
      assert.throws(() => validateRuntimeCase(copy), /runtime.*prefix/);
    }
  }
  for (const mutate of [
    (copy) => { delete copy.input.writer.compressor; },
    (copy) => { copy.input.localEdits[0].path = []; },
    (copy) => { copy.expected.observations[0].pendingCount = 0; },
    (copy) => { copy.input.writer.clientId = "another-writer"; },
  ]) {
    const copy = structuredClone(batch);
    mutate(copy);
    assert.throws(() => validateRuntimeCase(copy), /batched-commits/);
  }
});

test("container corpus preserves full runtime cases alongside scoped foundation evidence", {
  timeout: 120_000,
}, async (t) => {
  const output = await mkdtemp(join(tmpdir(), "watershed-container-corpus-"));
  t.after(() => rm(output, { recursive: true, force: true }));

  const cases = await capture(output);
  assert.deepEqual(cases.map(({ id, domain }) => [id, domain]), expectedCases);
  for (const value of cases.filter(({ input }) => input.service === "LocalDeltaConnectionServer")) {
    assert.equal(value.formatVersion, 1);
    assert.deepEqual(value.reference, {
      package: "@fluidframework/tree",
      version: "3.1.0",
      commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
    });
    assert(Array.isArray(value.input.schedules) && value.input.schedules.length > 0);
    assert(Array.isArray(value.expected.observations) && value.expected.observations.length > 0);
    assert(Array.isArray(value.raw.messages) && value.raw.messages.length > 0);
    assert.equal(value.raw.snapshot.blobEncoding, "base64");
    assert(Object.keys(value.raw.snapshot.blobs).length > 0);
    assert(Object.keys(value.raw.snapshot.tree.trees).length > 0);
  }

  const bootstrap = cases[0];
  assert.deepEqual(
    bootstrap.input.schedules.map(({ id }) => id),
    ["valid-bootstrap", "missing-tree-handle", "wrong-tree-handle-kind"],
  );
  assert(bootstrap.expected.observations.some(({ rejection }) => /missing/i.test(rejection)));
  assert(bootstrap.expected.observations.some(({ rejection }) => rejection === "wrong-tree-handle-kind"));
  assert.match(bootstrap.expected.observations[0].bootstrapPath, /\/root$/);
  assert(bootstrap.expected.observations[0].treePath.split("/").filter(Boolean).length >= 2);
  assertSnapshot(bootstrap.input.decoderInput.initialSnapshot);
  assert(bootstrap.input.decoderInput.bootstrapMessages.length >= 3);
  assert(bootstrap.input.decoderInput.bootstrapMessages.every(({ contents }) =>
    typeof contents === "string" && contents.includes('"key":"tree"')));

  const batched = cases[1];
  assert(batched.raw.groupedCommits.length > 0);
  assert(batched.raw.groupedCommits.some(({ commits }) => commits.length >= 3));
  for (const group of batched.raw.groupedCommits) {
    assert(Number.isInteger(group.outerSequenceNumber));
    assert.deepEqual(group.commits.map(({ innerPosition }) => innerPosition),
      group.commits.map((_commit, index) => index));
  }
  assertSnapshot(batched.input.decoderInput.initialSnapshot);
  assert(batched.input.decoderInput.groupedWireMessages.length > 0);
  assert(batched.input.decoderInput.groupedWireMessages.every(({ contents }) =>
    JSON.parse(contents).type === "groupedBatch"));

  const reconnect = cases[2];
  assert.deepEqual(
    reconnect.input.schedules.map(({ id }) => id),
    ["server-accepted-before-ack", "never-submitted-before-reconnect"],
  );
  assert(reconnect.expected.observations.some(({ status }) => status === "accepted-before-ack"));
  assert(reconnect.expected.observations.some(({ status }) => status === "never-submitted"));
  assertSnapshot(reconnect.input.replayInput.initialSnapshot);
  assertSerializedPendingState(reconnect.input.replayInput.acceptedBeforeAck.pendingLocalState);
  assert(reconnect.input.replayInput.acceptedBeforeAck.sequencedMessages.length > 0);
  assertSerializedPendingState(reconnect.input.replayInput.neverSubmitted.pendingLocalState);
  assert(reconnect.input.replayInput.neverSubmitted.sequencedMessagesAfterReconnect.length > 0);

  const tail = cases[3];
  assert(tail.raw.summary.referenceSequenceNumber < tail.raw.publication.sequenceNumber);
  assert(tail.raw.summaryToPublicationMessages.some(({ dataEdit }) => dataEdit === true));
  assert(tail.expected.observations.some(({ checkpoint }) => checkpoint === "replayed-through-publication"));
  assert(tail.expected.observations.some(({ checkpoint }) => checkpoint === "later-edit-after-reload"));
  assert.equal(tail.expected.observations[0].root.point.y, 0);
  assert.equal(tail.expected.observations.at(-1).root.point.y, 21);
  assertSnapshot(tail.input.replayInput.snapshotAtS);
  assert(tail.input.replayInput.summaryToPublicationMessages.length > 0);
  assert(tail.input.replayInput.laterTailMessages.length > 0);
  assert(tail.input.replayInput.summaryToPublicationMessages.every(({ sequenceNumber }) =>
    sequenceNumber > tail.input.replayInput.summaryReferenceSequenceNumber
    && sequenceNumber <= tail.input.replayInput.publicationSequenceNumber));
  assert(tail.input.replayInput.laterTailMessages.every(({ sequenceNumber }) =>
    sequenceNumber > tail.input.replayInput.publicationSequenceNumber));

  const matrix = cases[4];
  assert.deepEqual(matrix.expected.writerMatrix, [{
    writer: "upstream",
    reader: "upstream",
    status: "implemented",
    reloadAndEdit: true,
  }]);
  assert.deepEqual(matrix.input.nativeCells, [
    { writer: "upstream", reader: "native", status: "unimplemented" },
    { writer: "native", reader: "upstream", status: "unimplemented" },
    { writer: "native", reader: "native", status: "unimplemented" },
  ]);
  assertSnapshot(matrix.input.upstreamWriterInput.snapshot);
  assert(matrix.input.upstreamWriterInput.laterTailMessages.length > 0);
  assert(matrix.input.upstreamWriterInput.laterTailMessages.every(({ sequenceNumber }) =>
    sequenceNumber > matrix.input.upstreamWriterInput.publicationSequenceNumber));
});

test("container corpus is byte-reproducible in fresh deterministic processes", {
  timeout: 180_000,
}, async (t) => {
  const root = await mkdtemp(join(tmpdir(), "watershed-container-determinism-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const first = join(root, "first");
  const second = join(root, "second");
  const program = [
    'Object.defineProperty(globalThis.performance,"now",{value:()=>0});',
    'const { captureContainers } = await import("./container-corpus.mjs");',
    "await captureContainers(process.argv[1]);",
  ].join("");
  const options = {
    cwd: new URL(".", import.meta.url),
    env: { ...process.env, WATERSHED_ORACLE_DETERMINISTIC: "1" },
    timeout: 90_000,
  };
  for (const output of [first, second]) {
    await execute(process.execPath, [
      "--import", new URL("./determinism.mjs", import.meta.url).href,
      "--input-type=module", "-e", program, output,
    ], options);
  }
  const [firstBytes, secondBytes] = await Promise.all([
    readFile(join(first, "container-cases.json")),
    readFile(join(second, "container-cases.json")),
  ]);
  assert(firstBytes.equals(secondBytes));
});

test("container producer supplies separate foundation cases without claiming runtime replay", async (t) => {
  const output = await mkdtemp(join(tmpdir(), "watershed-foundation-corpus-"));
  t.after(() => rm(output, { recursive: true, force: true }));
  const corpus = await capture(output);
  for (const [id, domain] of [
    ["container-foundations", "container"],
    ["summary-foundations", "summary"],
  ]) {
    const value = corpus.find((entry) => entry.id === id);
    assert(value, `Missing independently replayable ${id}`);
    assert.equal(value.domain, domain);
    assert.notEqual(value.input.service, "LocalDeltaConnectionServer");
    assert(Object.keys(value.input).length > 0);
    assert(value.expected.observations.length > 0);
    assert(Object.keys(value.raw).length > 0);
    assert(!Object.hasOwn(value.expected, "writerMatrix"));
  }
});

function snapshotBlob(snapshot, path) {
  const parts = path.split("/").filter(Boolean);
  let tree = snapshot.tree;
  for (const part of parts.slice(0, -1)) tree = tree.trees[part];
  const id = tree.blobs[parts.at(-1)];
  assert.equal(typeof snapshot.blobs[id], "string", `Missing ${path}`);
  return JSON.parse(Buffer.from(snapshot.blobs[id], "base64").toString("utf8"));
}

test("summary persistence inputs retain detached history and advance enclosing metadata", async (t) => {
  const output = await mkdtemp(join(tmpdir(), "watershed-summary-persistence-"));
  t.after(() => rm(output, { recursive: true, force: true }));
  const matrix = (await capture(output)).find(({ id }) => id === "summary-writer-matrix");
  assert(Array.isArray(matrix.input.persistenceStates), "Missing complete persistence inputs");
  const states = matrix.input.persistenceStates;
  assert.deepEqual(states.map(({ id }) => id),
    ["initial", "concurrent-detached", "after-peer-leave", "after-nontree-tail"]);
  for (const state of states) {
    assertSnapshot(state.snapshot);
    const attributes = snapshotBlob(state.snapshot, "/.protocol/attributes");
    assert.equal(state.sequenceNumber, attributes.sequenceNumber);
    assert.equal(state.minimumSequenceNumber, attributes.minimumSequenceNumber);
    assert(state.tail.every(({ sequenceNumber }, index) =>
      sequenceNumber === state.sequenceNumber + index + 1));
  }
  assert.deepEqual(matrix.expected.persistenceObservations.map(({ id }) => id),
    states.map(({ id }) => id));
  assert(matrix.expected.persistenceObservations.every(({ continuationObserved }) =>
    continuationObserved === true));
  const retained = snapshotBlob(states[1].snapshot,
    "/.channels/A/.channels/_C/indexes/DetachedFieldIndex/DetachedFieldIndexBlob");
  assert(retained.data.length > 0, "Summary lost detached fields");
  const history = snapshotBlob(states[1].snapshot,
    "/.channels/A/.channels/_C/indexes/EditManager/String");
  assert(history.trunk.length > 0, "Summary lost retained trunk");
  assert(history.branches.length > 0, "Summary lost peer branch bases");
  const initialHistory = snapshotBlob(states[0].snapshot,
    "/.channels/A/.channels/_C/indexes/EditManager/String");
  assert.deepEqual(initialHistory.trunk, []);
  assert(states[0].sequenceNumber > 0, "Empty history must not imply an empty document");
  const retainedAfterTail = snapshotBlob(states[3].snapshot,
    "/.channels/A/.channels/_C/indexes/EditManager/String");
  assert(retainedAfterTail.trunk.some(({ sequenceNumber }) =>
    sequenceNumber < states[3].minimumSequenceNumber),
  "Non-tree messages must not be mistaken for tree retention advancement");
  const metadata = states.map(({ snapshot }) => snapshotBlob(snapshot, "/.metadata"));
  assert(metadata[2].summaryNumber > metadata[1].summaryNumber);
  assert.equal(metadata[2].lastMessage.sequenceNumber, states[2].sequenceNumber);
  const members = states.slice(1).map(({ snapshot }) =>
    snapshotBlob(snapshot, "/.protocol/quorumMembers").map(([id]) => id));
  assert(members[0].includes(matrix.input.departedPeer));
  assert(!members[1].includes(matrix.input.departedPeer));
  assert(states[2].minimumSequenceNumber > states[1].minimumSequenceNumber);
});
