import assert from "node:assert/strict";
import { test } from "node:test";
import {
  loadRequests, readCell, runArtifactInterop, runReloadMatrix, validateResults,
  validateSummaryArtifact,
} from "./summary-interop.mjs";

const implementations = ["upstream", "javascript", "erlang"];
const reference = {
  package: "@fluidframework/tree",
  version: "3.1.0",
  commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
};
const point = (x, y) => ({
  type: "org.watershed.shared-tree.m1.Point",
  fields: {
    x: [{ type: "com.fluidframework.leaf.number", value: x }],
    y: [{ type: "com.fluidframework.leaf.number", value: y }],
  },
});
const cells = Object.fromEntries(implementations.map((writer, writerIndex) => [
  writer,
  Object.fromEntries(implementations.map((reader, readerIndex) => [
    reader,
    {
      runId: "run",
      profileDigest: "a".repeat(64),
      writer,
      reader,
      writerVersion: `${writer}-commit`,
      loadedVersion: `${writer}-commit`,
      readerInstanceId: `${writer}-${reader}-reader`,
      snapshotSequenceNumber: 4 + writerIndex,
      dataEditSequenceNumber: 8 + writerIndex,
      publicationSequenceNumber: 12 + writerIndex,
      replayWatermark: 16 + readerIndex,
      replayStartSequenceNumber: 4 + writerIndex,
      replayEvidence: reader === "upstream"
        ? "upstream-delta-storage"
        : "native-handshake",
      selectedSummaryRequests: [`${writer}-commit`],
      scenarioId: "summary-tail",
      loaded: true,
      continuedEditing: true,
      peerObservedEdit: true,
      pendingTreeCount: 0,
      inflightSubmissionCount: 0,
      wholeTree: { schemaId: "org.watershed.shared-tree.m1.Root" },
      retained: {
        visible: { x: 3, y: 4 },
        detached: { x: 42, y: 7 },
        removed: [[1027, 4, point(42, 7)]],
        writerIdentity: {
          clientIds: [`${writer}-client`],
          originatorIds: [`${writer}-originator`],
          resubmissions: writer === "upstream" ? [] : [
            { refresher: [1, 2] },
            { refresher: [42, 2] },
          ],
        },
        upstreamSelectedVersion: `${writer}-commit`,
        summaryConsumed: true,
      },
      documentId: `${writer}-document`,
      artifacts: [`reload/${writer}-${reader}.json`],
    },
  ])),
]));

test("reload matrix rejects unmeasured selected-summary loads", () => {
  assert.equal(Object.keys(validateResults(cells)).length, 3);
  for (const [label, mutation] of [
    ["missing loaded version", (copy) => {
      delete copy.upstream.javascript.loadedVersion;
    }],
    ["wrong loaded version", (copy) => {
      copy.upstream.javascript.loadedVersion = "other";
    }],
    ["reused reader", (copy) => {
      copy.upstream.javascript.readerInstanceId =
        copy.upstream.upstream.readerInstanceId;
    }],
    ["no intervening data", (copy) => {
      copy.upstream.javascript.dataEditSequenceNumber =
        copy.upstream.javascript.snapshotSequenceNumber;
    }],
    ["no selected requests", (copy) => {
      copy.upstream.javascript.selectedSummaryRequests = [];
    }],
    ["false continuation", (copy) => {
      copy.upstream.javascript.continuedEditing = false;
    }],
    ["origin replay", (copy) => {
      copy.upstream.javascript.replayStartSequenceNumber = 0;
    }],
    ["unmeasured protocol fallback", (copy) => {
      copy.upstream.javascript.replayEvidence = "selected-summary-protocol";
    }],
  ]) {
    const copy = structuredClone(cells);
    mutation(copy);
    assert.throws(() => validateResults(copy), undefined, label);
  }
});

test("reload matrix proves detached identity from fresh restored content", () => {
  assert.equal(Object.keys(validateResults(cells)).length, 3);
  for (const [label, mutation] of [
    ["stale restored detached content", (copy) => {
      copy.upstream.javascript.retained.removed = [[1027, 4, point(1, 2)]];
    }],
    ["wrong restored detached identity", (copy) => {
      copy.upstream.javascript.retained.detached = { x: 7, y: 42 };
      copy.upstream.javascript.retained.removed = [[1027, 4, point(7, 42)]];
    }],
  ]) {
    const copy = structuredClone(cells);
    mutation(copy);
    assert.throws(() => validateResults(copy), undefined, label);
  }
});

test("native replay start prefers delivered operations over stale handshake context", () => {
  const version = "selected-version";
  const load = loadRequests({
    http: [
      { status: 200, path: `/git/commits/${version}` },
      { status: 200, path: "/git/trees/tree" },
      { status: 200, path: "/git/blobs/blob" },
    ],
    delivered: [{
      direction: "inbound",
      kind: "op",
      sequenceNumbers: [130],
    }],
    handshakes: [{
      checkpointSequenceNumber: 130,
      summarySequenceNumber: 0,
      initialMessageSequenceNumbers: [130],
    }],
  }, version, 123);
  assert.deepEqual(load, {
    loadedVersion: version,
    selectedSummaryRequests: [version],
    replayStartSequenceNumber: 129,
    replayEvidence: "native-delivery",
  });
});

test("native handshake replay start uses initial messages before summary context", () => {
  const version = "selected-version";
  const load = loadRequests({
    http: [
      { status: 200, path: `/git/commits/${version}` },
      { status: 200, path: "/git/trees/tree" },
      { status: 200, path: "/git/blobs/blob" },
    ],
    delivered: [],
    handshakes: [{
      checkpointSequenceNumber: 124,
      summarySequenceNumber: 0,
      initialMessageSequenceNumbers: [124],
    }],
  }, version, 123);
  assert.equal(load.replayStartSequenceNumber, 123);
  assert.equal(load.replayEvidence, "native-handshake");
});

test("native handshake excludes the redundant server prefix before selected summary", () => {
  const version = "selected-version";
  const load = loadRequests({
    http: [
      { status: 200, path: `/git/commits/${version}` },
      { status: 200, path: "/git/trees/tree" },
      { status: 200, path: "/git/blobs/blob" },
    ],
    delivered: [],
    handshakes: [{
      checkpointSequenceNumber: 29,
      initialMessageSequenceNumbers: Array.from({ length: 29 }, (_, index) => index + 1),
    }],
  }, version, 15);
  assert.equal(load.replayStartSequenceNumber, 15);
  assert.equal(load.replayEvidence, "native-handshake");
});

test("native summary load rejects absent replay evidence", () => {
  const version = "selected-version";
  assert.throws(() => loadRequests({
    http: [
      { status: 200, path: `/git/commits/${version}` },
      { status: 200, path: "/git/trees/tree" },
      { status: 200, path: "/git/blobs/blob" },
      { status: 200, path: "/deltas/document?from=15" },
    ],
    delivered: [],
    handshakes: [],
  }, version, 15), /lacks measured replay evidence/);
});

test("native summary load rejects a selected-summary handshake without applied tail", () => {
  const version = "selected-version";
  assert.throws(() => loadRequests({
    http: [
      { status: 200, path: `/git/commits/${version}` },
      { status: 200, path: "/git/trees/tree" },
      { status: 200, path: "/git/blobs/blob" },
      { status: 200, path: "/deltas/document?from=15" },
    ],
    delivered: [],
    handshakes: [{
      checkpointSequenceNumber: 15,
      initialMessageSequenceNumbers: Array.from(
        { length: 15 },
        (_, index) => index + 1,
      ),
    }],
  }, version, 15), /lacks measured replay evidence/);
});

test("reload tree mismatch remains primary when reader close also fails", async () => {
  const closeError = new Error("reader close failed");
  let closeCalls = 0;
  const adapter = {
    instanceId: "reader",
    async awaitSynced() {},
    evidence() {
      return {
        http: [
          { status: 200, path: "/git/commits/version" },
          { status: 200, path: "/git/trees/tree" },
          { status: 200, path: "/git/blobs/blob" },
        ],
        delivered: [],
        handshakes: [{
          checkpointSequenceNumber: 16,
          initialMessageSequenceNumbers: [16],
        }],
      };
    },
    async checkpoint() {
      return { wholeTree: { wrong: true } };
    },
    async close() {
      closeCalls += 1;
      throw closeError;
    },
  };
  const row = {
    documentId: "document",
    jwt: "jwt",
    version: "version",
    snapshotSequenceNumber: 15,
    publicationSequenceNumber: 16,
    observer: {
      data: {
        view: {
          root: {
            enabled: false,
            marker: null,
            point: { x: 3, y: 4 },
            rating: 1,
            title: "title",
          },
        },
      },
    },
  };
  let failure;
  try {
    await readCell(
      { tenantId: "fluid" },
      { runId: "run", viewSchema: "schema" },
      row,
      "javascript",
      {
        getPublishedVersion: async () => "version",
        makeNativeAdapter: async () => adapter,
      },
    );
  } catch (error) {
    failure = error;
  }
  assert.match(failure.message, /loaded a different typed root/);
  assert.deepEqual(failure.cleanupErrors, [closeError]);
  assert.equal(closeCalls, 1);
});

test("fresh summary artifacts require target, reference, cases and full hierarchy", () => {
  const artifact = {
    target: "javascript", reference, cases: [{
      id: "summary-tail", snapshotSequenceNumber: 7,
      publicationSequenceNumber: 7,
      tree: { type: "tree", entries: [[".metadata", {
        type: "blob", base64: "e30=",
      }]] },
    }],
  };
  validateSummaryArtifact(artifact, "javascript", ["summary-tail"]);
  for (const change of [
    (copy) => { copy.target = "erlang"; },
    (copy) => { copy.reference.commit = "stale"; },
    (copy) => { copy.cases = []; },
    (copy) => { copy.cases[0].tree.entries = []; },
    (copy) => { copy.cases[0].tree.entries[0][1].base64 = "@@"; },
  ]) {
    const copy = structuredClone(artifact);
    change(copy);
    assert.throws(() =>
      validateSummaryArtifact(copy, "javascript", ["summary-tail"]));
  }
});

test("artifact coordinator rejects missing and stale target output", async () => {
  await assert.rejects(
    runArtifactInterop({
      produce: async () => {},
      cases: ["summary-tail"],
    }),
    /Missing .* artifact/,
  );
});

test("reload runner requires the combined-run context", async () => {
  await assert.rejects(
    runReloadMatrix({}, {}),
    /runReloadMatrix context requires runId/,
  );
});
