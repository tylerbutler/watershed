import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { test } from "node:test";
import {
  continueArrayReader,
  loadRequests,
  nativeStorageLoad,
  storageLoad,
  mapEntryMatches,
  readCell,
  runArrayReloadMatrix,
  runArtifactInterop,
  restoreArrayReader,
  runMapReloadMatrix,
  runReloadMatrix,
  runSchemaReloadMatrix,
  validateArrayResults,
  validateIdentifierReloadResults,
  validateMapResults,
  validateResults,
  validateSchemaReloadResults,
  validateSummaryArtifact,
  validateTransactionReloadResults,
} from "./summary-interop.mjs";

test("array reader continuation preserves pre-existing right-side tail values", async () => {
  const initial = {
    left: [
      { label: "duplicate", x: 1 },
      { label: "duplicate", x: 1 },
      [{ label: "nested", x: 2 }],
    ],
    right: [
      { inside: { label: "map-child", x: 3 } },
      { label: "moved", x: 4 },
      { label: "after-summary", x: 7 },
    ],
  };
  const state = structuredClone(initial);
  const adapter = {
    async arrayMove(sourcePath, sourceStart, sourceEnd, destinationPath, destinationGap) {
      const source = state[sourcePath[0]];
      const destination = state[destinationPath[0]];
      destination.splice(destinationGap, 0, ...source.splice(sourceStart, sourceEnd - sourceStart));
    },
    async set(path, value) {
      state[path[0]][Number(path[1])][path[2]] = value;
    },
  };
  await continueArrayReader(adapter, "continued");
  assert.deepEqual(state.right.at(-1), initial.right.at(-1));
  await restoreArrayReader(adapter);
  assert.deepEqual(state, initial);
});

const implementations = ["upstream", "javascript", "erlang"];
const identifierReloadCells = Object.fromEntries(implementations.map((writer) => [
  writer,
  Object.fromEntries(implementations.map((reader) => [
    reader,
    {
      runId: "run",
      profileDigest: "a".repeat(64),
      profile: "identifier",
      writer,
      reader,
      writerVersion: `${writer}-identifier-version`,
      loadedVersion: `${writer}-identifier-version`,
      readerInstanceId: `${writer}-${reader}-identifier-reader`,
      scenarioId: "identifier-summary-postload",
      loaded: true,
      writerAuthored: {
        defaultId: `${writer}-generated`,
        explicitId: "shared-custom-id",
      },
      postLoadAuthored: {
        author: reader,
        id: `${writer}-${reader}-generated`,
        originatorId: `${reader}-originator`,
        allocationRange: {
          sessionId: `${reader}-session`,
          ids: { first: 0, count: 1 },
        },
      },
      peerObservation: {
        implementation: writer === reader ? "upstream" : writer,
        id: `${writer}-${reader}-generated`,
        observed: true,
      },
      pendingTreeCount: 0,
      inflightSubmissionCount: 0,
      documentId: `${writer}-identifier-document`,
      artifacts: [`identifier-reload/${writer}-${reader}.json`],
    },
  ])),
]));
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
const mapRoot = {
  kind: "object",
  schemaId: "org.watershed.shared-tree.m2.MapRoot",
  fields: [[
    "items",
    {
      kind: "map",
      schemaId: "org.watershed.shared-tree.m2.DynamicMap",
      entries: [
        ["", { kind: "string", value: "empty" }],
        ["123", { kind: "number", value: 123 }],
        ["__proto__", { kind: "null" }],
        ["tail", { kind: "string", value: "after-summary" }],
        ["水", { kind: "boolean", value: true }],
      ],
    },
  ]],
};
const mapCells = Object.fromEntries(implementations.map((writer, writerIndex) => [
  writer,
  Object.fromEntries(implementations.map((reader, readerIndex) => [
    reader,
    {
      runId: "run",
      profileDigest: "a".repeat(64),
      profile: "map",
      writer,
      reader,
      writerVersion: `${writer}-map-commit`,
      loadedVersion: `${writer}-map-commit`,
      readerInstanceId: `${writer}-${reader}-map-reader`,
      snapshotSequenceNumber: 20 + writerIndex,
      dataEditSequenceNumber: 24 + writerIndex,
      publicationSequenceNumber: 28 + writerIndex,
      replayWatermark: 32 + readerIndex,
      replayStartSequenceNumber: 20 + writerIndex,
      replayEvidence: reader === "upstream"
        ? "upstream-delta-storage"
        : "native-handshake",
      selectedSummaryRequests: [`${writer}-map-commit`],
      scenarioId: "map-summary-tail-retained",
      loaded: true,
      tailObserved: true,
      continuedEditing: true,
      peerObservedEdit: true,
      deletedEntryAbsent: true,
      pendingTreeCount: 0,
      inflightSubmissionCount: 0,
      wholeTree: mapRoot,
      retained: {
        removed: [[1027, 4, { type: "org.watershed.shared-tree.m2.Point" }]],
        deletedKey: "deleted",
        summaryConsumed: true,
      },
      documentId: `${writer}-map-document`,
      artifacts: [`map-reload/${writer}-${reader}.json`],
    },
  ])),
]));
const arrayPoint = (label, x) => ({
  kind: "object",
  schemaId: "org.watershed.shared-tree.m3.Point",
  fields: [
    ["label", { kind: "string", value: label }],
    ["x", { kind: "number", value: x }],
  ],
});
const removedArrayPoint = () => ({
  type: "org.watershed.shared-tree.m3.Point",
  fields: {
    label: [{ type: "com.fluidframework.leaf.string", value: "deleted" }],
    x: [{ type: "com.fluidframework.leaf.number", value: 9 }],
  },
});
const nativeRemovedArrayPoint = () => ({
  kind: "object",
  schemaId: "org.watershed.shared-tree.m3.Point",
  fields: [
    ["label", { kind: "string", value: "deleted" }],
    ["x", { kind: "number", value: 9 }],
  ],
});
const arrayValue = (elements) => ({
  kind: "array",
  schemaId: "org.watershed.shared-tree.m3.Items",
  elements,
});
const arrayMap = (entries) => ({
  kind: "map",
  schemaId: "org.watershed.shared-tree.m3.ArrayMap",
  entries,
});
const arrayTree = (writer, continuationLabel = undefined) => ({
  present: true,
  value: {
    kind: "object",
    schemaId: "org.watershed.shared-tree.m3.Root",
    fields: [
      ["byKey", arrayMap([
        ["", arrayValue([])],
        ["0", arrayValue([arrayPoint("numeric", 0)])],
      ])],
      ["left", arrayValue([
        ...(continuationLabel ? [arrayPoint(continuationLabel, 42)] : []),
        arrayPoint("duplicate", 1),
        arrayPoint("duplicate", 1),
        arrayValue([arrayPoint("nested", 2)]),
      ])],
      ["narrow", {
        kind: "array",
        schemaId: "org.watershed.shared-tree.m3.Points",
        elements: [],
      }],
      ["right", arrayValue([
        arrayMap([["inside", arrayPoint("map-child", 3)]]),
        ...(continuationLabel ? [] : [arrayPoint("moved", 4)]),
        arrayPoint(`after-summary-${writer}`, 7),
      ])],
    ],
  },
});
const arrayCells = Object.fromEntries(implementations.map((writer, writerIndex) => [
  writer,
  Object.fromEntries(implementations.map((reader, readerIndex) => [
    reader,
    {
      runId: "run",
      profileDigest: "a".repeat(64),
      profile: "array",
      writer,
      reader,
      writerVersion: `${writer}-array-commit`,
      loadedVersion: `${writer}-array-commit`,
      readerInstanceId: `${writer}-${reader}-array-reader`,
      snapshotSequenceNumber: 40 + writerIndex,
      dataEditSequenceNumber: 44 + writerIndex,
      publicationSequenceNumber: 48 + writerIndex,
      tailSequenceNumber: 52 + writerIndex,
      replayWatermark: 56 + readerIndex,
      replayStartSequenceNumber: 40 + writerIndex,
      replayEvidence: reader === "upstream"
        ? "upstream-delta-storage"
        : "native-handshake",
      selectedSummaryRequests: [`${writer}-array-commit`],
      scenarioId: "array-summary-tail-retained",
      loaded: true,
      tailObserved: true,
      continuedEditing: true,
      peerObservedEdit: true,
      pendingTreeCount: 0,
      inflightSubmissionCount: 0,
      wholeTree: arrayTree(writer),
      continuationTree: arrayTree(writer, `${writer}-${reader}-continuation`),
      peerWholeTree: arrayTree(writer, `${writer}-${reader}-continuation`),
      continuationLabel: `${writer}-${reader}-continuation`,
      retained: {
        removed: [[1027, 4, reader === "upstream"
          ? removedArrayPoint()
          : nativeRemovedArrayPoint()]],
        reader: reader,
        readerInstanceId: `${writer}-${reader}-array-reader`,
        source: reader === "upstream"
          ? "upstream-runtime-and-wire"
          : "native-runtime-snapshot",
        loadedVersion: `${writer}-array-commit`,
        snapshotSequenceNumber: 40 + writerIndex,
        sequenceNumber: 56 + readerIndex,
        selectedVersion: `${writer}-array-commit`,
        history: [{
          revision: 1,
          originatorId: `${reader}-originator`,
          changes: [{
            moveOut: { id: 0 },
            moveIn: { id: 0 },
          }],
        }],
        moveIdentity: {
          revision: 1,
          originatorId: `${reader}-originator`,
          moveOut: [{ id: 0, revision: 1 }],
          moveIn: [{ id: 0, revision: 1 }],
        },
        childEditObserved: true,
        summaryConsumed: true,
      },
      continuationIdentity: {
        clientId: `${reader}-client`,
        referenceSequenceNumber: 52 + writerIndex,
        revisions: [{ revision: 1, originatorId: `${reader}-originator` }],
      },
      documentId: `${writer}-array-document`,
      artifacts: [`array-reload/${writer}-${reader}.json`],
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

test("identifier reload validation requires all nine post-load authoring cells", () => {
  assert.equal(Object.keys(validateIdentifierReloadResults(identifierReloadCells)).length, 3);
  for (const [label, mutation] of [
    ["writer", (copy) => { delete copy.erlang; }],
    ["reader", (copy) => { delete copy.javascript.erlang; }],
    ["post-load author", (copy) => {
      copy.upstream.javascript.postLoadAuthored.author = "upstream";
    }],
    ["peer observation", (copy) => {
      copy.erlang.upstream.peerObservation.observed = false;
    }],
    ["allocation", (copy) => {
      delete copy.javascript.javascript.postLoadAuthored.allocationRange;
    }],
  ]) {
    const copy = structuredClone(identifierReloadCells);
    mutation(copy);
    assert.throws(() => validateIdentifierReloadResults(copy), undefined, label);
  }
});

const transactionReloadCells = Object.fromEntries(
  ["upstream", "javascript", "erlang"].map((writer) => [
    writer,
    Object.fromEntries(["upstream", "javascript", "erlang"].map((reader) => [
      reader,
      {
        runId: "one-run",
        profileDigest: "a".repeat(64),
        profile: "array",
        writer,
        reader,
        writerVersion: `${writer}-version`,
        loadedVersion: `${writer}-version`,
        readerInstanceId: `${writer}-${reader}-reader`,
        scenarioId: "transaction-summary-postload",
        loaded: true,
        historyVerified: true,
        historyEvidence: {
          trunkCount: 3,
          pendingCount: 0,
          retainedCount: 0,
          composedCommitCount: 1,
          partialCommitCount: 0,
        },
        nodeIdentityVerified: true,
        constrainedNode: {
          field: "left",
          index: 0,
          label: "anchor",
          value: { kind: "object", fields: [["label", { value: "anchor" }]] },
        },
        writerAuthored: {
          outcome: "committed",
          outboundCount: 1,
          labels: [`${writer}-reload-a`, `${writer}-reload-b`],
        },
        postLoadAuthored: {
          author: reader,
          outcome: "committed",
          label: `${writer}-${reader}-postload`,
          outboundCount: 1,
          editsApplied: 2,
          nestedScopes: 1,
          sequencedCommitCount: 1,
          originatorId: `${reader}-originator`,
        },
        peerObservation: {
          implementation: "upstream",
          label: `${writer}-${reader}-postload`,
          observed: true,
        },
        pendingTreeCount: 0,
        inflightSubmissionCount: 0,
        documentId: `${writer}-transaction-document`,
        artifacts: ["transaction-reload/cell.json"],
      },
    ])),
  ]),
);

test("transaction reload validation requires nine atomic post-load cells", () => {
  assert.equal(
    Object.keys(validateTransactionReloadResults(transactionReloadCells)).length,
    3,
  );
  for (const [label, mutation] of [
    ["writer", (copy) => { delete copy.erlang; }],
    ["reader", (copy) => { delete copy.javascript.erlang; }],
    ["history", (copy) => { copy.upstream.javascript.historyVerified = false; }],
    ["restored composed commit", (copy) => {
      copy.upstream.javascript.historyEvidence.composedCommitCount = 0;
    }],
    ["split writer transaction", (copy) => {
      copy.javascript.erlang.historyEvidence.partialCommitCount = 1;
    }],
    ["restored pending commits", (copy) => {
      copy.erlang.javascript.historyEvidence.pendingCount = 1;
    }],
    ["missing history evidence", (copy) => {
      delete copy.upstream.upstream.historyEvidence;
    }],
    ["node identity", (copy) => {
      copy.upstream.erlang.nodeIdentityVerified = false;
    }],
    ["missing constrained node", (copy) => {
      delete copy.javascript.javascript.constrainedNode;
    }],
    ["constrained node position", (copy) => {
      copy.erlang.erlang.constrainedNode.index = 1;
    }],
    ["constrained node content", (copy) => {
      copy.erlang.upstream.constrainedNode.value = null;
    }],
    ["writer labels", (copy) => {
      copy.javascript.upstream.writerAuthored.labels = ["other"];
    }],
    ["post-load author", (copy) => {
      copy.upstream.javascript.postLoadAuthored.author = "upstream";
    }],
    ["atomicity", (copy) => {
      copy.erlang.erlang.postLoadAuthored.sequencedCommitCount = 2;
    }],
    ["nested scope", (copy) => {
      copy.erlang.javascript.postLoadAuthored.nestedScopes = 0;
    }],
    ["peer observation", (copy) => {
      copy.erlang.upstream.peerObservation.observed = false;
    }],
    ["reader instance reuse", (copy) => {
      copy.javascript.javascript.readerInstanceId =
        copy.upstream.upstream.readerInstanceId;
    }],
  ]) {
    const copy = structuredClone(transactionReloadCells);
    mutation(copy);
    assert.throws(() => validateTransactionReloadResults(copy), undefined, label);
  }
});

test("map reload matrix requires nine canonical tail and continuation cells", () => {
  assert.equal(Object.keys(validateMapResults(mapCells)).length, 3);
  for (const [label, mutation] of [
    ["missing cell", (copy) => { delete copy.upstream.javascript; }],
    ["wrong profile", (copy) => { copy.upstream.javascript.profile = "object"; }],
    ["noncanonical entries", (copy) => {
      copy.upstream.javascript.wholeTree.fields[0][1].entries.reverse();
    }],
    ["missing tail", (copy) => { copy.upstream.javascript.tailObserved = false; }],
    ["missing continuation", (copy) => {
      copy.upstream.javascript.peerObservedEdit = false;
    }],
    ["deleted entry restored", (copy) => {
      copy.upstream.javascript.deletedEntryAbsent = false;
    }],
    ["missing retained history", (copy) => {
      copy.upstream.javascript.retained.removed = [];
    }],
  ]) {
    const copy = structuredClone(mapCells);
    mutation(copy);
    assert.throws(() => validateMapResults(copy), undefined, label);
  }
});

test("map continuation observation requires the exact value", () => {
  const root = { items: new Map([["reader", "expected"]]) };
  assert.equal(mapEntryMatches(root, "reader", {
    kind: "string",
    value: "expected",
  }), true);
  assert.equal(mapEntryMatches(root, "reader", {
    kind: "string",
    value: "corrupt",
  }), false);
});

test("array reload matrix requires nine exact tail and continuation cells", () => {
  assert.equal(Object.keys(validateArrayResults(arrayCells)).length, 3);
  for (const [label, mutation] of [
    ["missing cell", (copy) => { delete copy.upstream.javascript; }],
    ["wrong profile", (copy) => { copy.upstream.javascript.profile = "map"; }],
    ["reordered array", (copy) => {
      copy.upstream.javascript.wholeTree.value.fields[1][1].elements.reverse();
    }],
    ["missing tail", (copy) => { copy.upstream.javascript.tailObserved = false; }],
    ["missing retained history", (copy) => {
      copy.upstream.javascript.retained.removed = [];
    }],
    ["wrong retained version", (copy) => {
      copy.upstream.javascript.retained.selectedVersion = "other";
    }],
    ["missing move identity", (copy) => {
      delete copy.upstream.javascript.retained.moveIdentity;
    }],
    ["mismatched move atom", (copy) => {
      copy.upstream.javascript.retained.moveIdentity.moveIn[0].id = 1;
    }],
    ["missing move revision", (copy) => {
      delete copy.upstream.javascript.retained.moveIdentity.moveOut[0].revision;
    }],
    ["corrupt continuation", (copy) => {
      copy.upstream.javascript.peerWholeTree.value.fields[3][1].elements[1]
        .fields[1][1].value = 41;
    }],
  ]) {
    const copy = structuredClone(arrayCells);
    mutation(copy);
    assert.throws(() => validateArrayResults(copy), undefined, label);
  }
});

test("array reload retained evidence is required for every reader", () => {
  for (const writer of implementations) {
    for (const reader of implementations) {
      for (const [label, mutation, message] of [
        ["removed content", (retained) => { retained.removed = []; },
          /retained deleted content/i],
        ["persisted history", (retained) => { retained.history = []; },
          /retained summary history/i],
      ]) {
        const copy = structuredClone(arrayCells);
        mutation(copy[writer][reader].retained);
        assert.throws(
          () => validateArrayResults(copy),
          message,
          `${writer}->${reader} ${label}`,
        );
      }
    }
  }
});

test("array reload binds retained evidence to the loaded reader and summary", () => {
  for (const [label, mutation] of [
    ["wrong reader", (cell) => { cell.retained.reader = "upstream"; }],
    ["wrong reader instance", (cell) => {
      cell.retained.readerInstanceId = "another-reader";
    }],
    ["wrong evidence source", (cell) => {
      cell.retained.source = "upstream-runtime-snapshot";
    }],
    ["wrong loaded version", (cell) => {
      cell.retained.loadedVersion = "another-version";
    }],
    ["wrong snapshot sequence", (cell) => {
      cell.retained.snapshotSequenceNumber -= 1;
    }],
    ["evidence before load checkpoint", (cell) => {
      cell.retained.sequenceNumber = cell.snapshotSequenceNumber - 1;
    }],
  ]) {
    const copy = structuredClone(arrayCells);
    mutation(copy.upstream.javascript);
    assert.throws(() => validateArrayResults(copy), undefined, label);
  }
});

function storageHttp(version, snapshotSequenceNumber) {
  return [
    {
      status: 200,
      path: `/git/commits/${version}`,
      responseHash: "1".repeat(64),
      storageResponse: {
        kind: "commit",
        requestedId: version,
        treeId: "root-tree",
      },
    },
    {
      status: 200,
      path: "/git/trees/root-tree",
      responseHash: "2".repeat(64),
      storageResponse: {
        kind: "tree",
        requestedId: "root-tree",
        entries: [{ path: ".protocol", type: "tree", id: "protocol-tree" }],
      },
    },
    {
      status: 200,
      path: "/git/trees/protocol-tree",
      responseHash: "3".repeat(64),
      storageResponse: {
        kind: "tree",
        requestedId: "protocol-tree",
        entries: [{ path: "attributes", type: "blob", id: "attributes-blob" }],
      },
    },
    {
      status: 200,
      path: "/git/blobs/attributes-blob",
      responseHash: "4".repeat(64),
      responseSnapshotSequenceNumber: snapshotSequenceNumber,
      storageResponse: {
        kind: "blob",
        requestedId: "attributes-blob",
        snapshotSequenceNumber,
      },
    },
  ].map((observation, index) => {
    const identity = observation.storageResponse;
    const response = identity.kind === "commit"
      ? { sha: identity.requestedId, tree: { sha: identity.treeId } }
      : identity.kind === "tree"
        ? { sha: identity.requestedId, tree: identity.entries.map(({ id, ...entry }) =>
            ({ ...entry, sha: id })) }
        : { sha: identity.requestedId, encoding: "base64",
            content: Buffer.from(JSON.stringify({
              sequenceNumber: snapshotSequenceNumber, minimumSequenceNumber: 0,
            })).toString("base64") };
    const bytes = Buffer.from(JSON.stringify(response));
    return { ...observation, id: index + 1, method: "GET",
      responseBody: bytes.toString("base64"),
      responseHash: createHash("sha256").update(bytes).digest("hex") };
  });
}

test("completion binds native storage identity to request and response bytes", async (t) => {
  for (const [label, mutate] of [
    ["unrequested blob", (http) => { http[3].path = "/git/blobs/other"; }],
    ["copied hash", (http) => { http[3].responseHash = "a".repeat(64); }],
    ["copied sequence", (http) => { http[3].storageResponse.snapshotSequenceNumber = 20; }],
    ["copied tree", (http) => { http[0].storageResponse.treeId = "other"; }],
    ["changed raw body", (http) => {
      http[3].responseBody = Buffer.from('{"sequenceNumber":20,"minimumSequenceNumber":0}')
        .toString("base64");
    }],
    ["conflicting response to the same request", (http) => {
      http.push({ ...storageHttp("version", 20)[3], id: 5 });
    }],
  ]) {
    await t.test(label, () => {
      const http = storageHttp("version", 18);
      assert.equal(nativeStorageLoad(http, "version").snapshotSequenceNumber, 18);
      mutate(http);
      assert.throws(() => nativeStorageLoad(http, "version"));
    });
  }
});

test("review follow-up validates raw storage responses without derived metadata", async (t) => {
  await t.test("conflicting duplicate cannot hide by deleting storageResponse", () => {
    const http = storageHttp("version", 18);
    assert.equal(nativeStorageLoad(http, "version").snapshotSequenceNumber, 18);
    const duplicate = { ...storageHttp("version", 20)[3], id: 5 };
    delete duplicate.storageResponse;
    http.push(duplicate);
    assert.throws(() => nativeStorageLoad(http, "version"), /conflicting responses/);
  });
  await t.test("derived metadata is optional on valid responses", () => {
    const http = storageHttp("version", 18);
    for (const observation of http) delete observation.storageResponse;
    assert.equal(nativeStorageLoad(http, "version").snapshotSequenceNumber, 18);
  });
  for (const [label, mutate, expected] of [
    ["missing bytes", (response) => { delete response.responseBody; }, /raw response bytes/],
    ["copied hash", (response) => { response.responseHash = "a".repeat(64); }, /hash/],
    ["conflicting non-attributes blob", (response, http) => {
      const bytes = Buffer.from('{"encoding":"utf-8","content":"different"}');
      http.push({ ...response, id: 6, responseBody: bytes.toString("base64"),
        responseHash: createHash("sha256").update(bytes).digest("hex") });
    }, /conflicting responses/],
  ]) {
    await t.test(label, () => {
      const http = storageHttp("version", 18);
      const bytes = Buffer.from('{"encoding":"utf-8","content":"tree data"}');
      const response = { id: 5, method: "GET", path: "/git/blobs/content",
        status: 200, responseBody: bytes.toString("base64"),
        responseHash: createHash("sha256").update(bytes).digest("hex") };
      http.push(response);
      assert.equal(nativeStorageLoad(http, "version").snapshotSequenceNumber, 18);
      mutate(response, http);
      assert.throws(() => nativeStorageLoad(http, "version"), expected);
    });
  }
});

test("completion binds upstream load to the requested snapshot and blob bytes", async (t) => {
  const body = Buffer.from('{"sequenceNumber":18,"minimumSequenceNumber":0}');
  const observations = [
    { operation: "getVersions", request: [null, 1], versions: [{ id: "version", treeId: "root" }] },
    { operation: "getSnapshotTree", request: [{ id: "version", treeId: "root" }],
      id: "root", tree: { id: "root", blobs: {}, trees: {
        ".protocol": { id: "protocol", trees: {}, blobs: { attributes: "blob" } },
      } } },
    { operation: "readBlob", id: "blob", byteLength: body.length,
      hash: createHash("sha256").update(body).digest("hex"),
      responseBody: body.toString("base64"), snapshotSequenceNumber: 18 },
    { operation: "fetchMessages", from: 18 },
  ];
  for (const observation of observations.slice(0, 2)) {
    const bytes = Buffer.from(JSON.stringify(observation.versions ?? observation.tree));
    observation.responseBody = bytes.toString("base64");
    observation.hash = createHash("sha256").update(bytes).digest("hex");
  }
  for (const [label, mutate] of [
    ["another snapshot request", (raw) => { raw[1].request[0].id = "other"; }],
    ["copied blob sequence", (raw) => { raw[2].snapshotSequenceNumber = 20; }],
    ["copied blob hash", (raw) => { raw[2].hash = "a".repeat(64); }],
  ]) {
    await t.test(label, () => {
      const raw = structuredClone(observations);
      assert.equal(storageLoad(raw, "version").snapshotSequenceNumber, 18);
      mutate(raw);
      assert.throws(() => storageLoad(raw, "version"));
    });
  }
});

test("native replay start prefers delivered operations over stale handshake context", () => {
  const version = "selected-version";
  const load = loadRequests({
    http: storageHttp(version, 0),
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
  assert.equal(load.rawLoadIdentity.commitId, version);
  assert.equal(load.rawLoadIdentity.rootTreeId, "root-tree");
  assert.equal(load.rawLoadIdentity.protocolTreeId, "protocol-tree");
  assert.equal(load.rawLoadIdentity.blobId, "attributes-blob");
  assert.equal(load.rawLoadIdentity.responseHash, storageHttp(version, 0).at(-1).responseHash);
  assert.equal(load.snapshotSequenceNumber, 0);
  assert.equal(load.replayStartSequenceNumber, 129);
  assert.equal(load.replayEvidence, "native-delivery");
});

test("native handshake replay start uses initial messages before summary context", () => {
  const version = "selected-version";
  const load = loadRequests({
    http: storageHttp(version, 0),
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

test("native omitted summary context identifies the sequence-zero snapshot", () => {
  const version = "selected-version";
  const load = loadRequests({
    http: storageHttp(version, 0),
    delivered: [],
    handshakes: [{
      checkpointSequenceNumber: 1,
      initialMessageSequenceNumbers: [1],
    }],
  }, version);
  assert.equal(load.snapshotSequenceNumber, 0);
  assert.equal(load.rawLoadIdentity.snapshotSequenceNumber, 0);
  assert.equal(load.replayStartSequenceNumber, 0);
});

test("native storage identity overrides copied runtime state", () => {
  const version = "selected-version";
  const load = loadRequests({
    http: storageHttp(version, 18),
    delivered: [],
    nativeLoadIdentities: [{
      snapshotSequenceNumber: 18,
      observedSequenceNumber: 31,
    }],
    handshakes: [{
      checkpointSequenceNumber: 31,
      initialMessageSequenceNumbers: Array.from(
        { length: 31 },
        (_, index) => index + 1,
      ),
    }],
  }, version);
  assert.equal(load.snapshotSequenceNumber, 18);
  assert.equal(load.rawLoadIdentity.responseHash, storageHttp(version, 18).at(-1).responseHash);
  assert.equal(load.replayStartSequenceNumber, 18);
});

test("native selected blob identity overrides copied response scalars", () => {
  const version = "selected-version";
  const load = loadRequests({
    http: storageHttp(version, 18).map((observation) => ({
      ...observation,
      responseSnapshotSequenceNumber: observation.storageResponse.kind === "blob"
        ? 19
        : observation.responseSnapshotSequenceNumber,
    })),
    delivered: [],
    nativeLoadIdentities: [{
      snapshotSequenceNumber: 19,
      observedSequenceNumber: 31,
    }],
    handshakes: [{
      checkpointSequenceNumber: 31,
      initialMessageSequenceNumbers: Array.from(
        { length: 31 },
        (_, index) => index + 1,
      ),
    }],
  }, version);
  assert.equal(load.snapshotSequenceNumber, 18);
  assert.equal(load.rawLoadIdentity.blobId, "attributes-blob");
  assert.equal(load.replayStartSequenceNumber, 18);
});

test("native handshake excludes the redundant server prefix before selected summary", () => {
  const version = "selected-version";
  const load = loadRequests({
    http: storageHttp(version, 15),
    delivered: [],
    handshakes: [{
      checkpointSequenceNumber: 29,
      summarySequenceNumber: 15,
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
      ...storageHttp(version, 15),
      { status: 200, path: "/deltas/document?from=15" },
    ],
    delivered: [],
    handshakes: [{
      checkpointSequenceNumber: 15,
      summarySequenceNumber: 15,
      initialMessageSequenceNumbers: [],
    }],
  }, version, 15), /lacks measured replay evidence/);
});

test("native summary load rejects a selected-summary handshake without applied tail", () => {
  const version = "selected-version";
  assert.throws(() => loadRequests({
    http: [
      ...storageHttp(version, 15),
      { status: 200, path: "/deltas/document?from=15" },
    ],
    delivered: [],
    handshakes: [{
      checkpointSequenceNumber: 15,
      summarySequenceNumber: 15,
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
        http: storageHttp("version", 15),
        delivered: [],
        handshakes: [{
          checkpointSequenceNumber: 16,
          summarySequenceNumber: 15,
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
  const schema = Buffer.from(JSON.stringify({
    nodes: { Root: { kind: { object: {} } } },
    root: { kind: "Value", types: ["Root"] },
  })).toString("base64");
  const artifact = {
    target: "javascript", reference, cases: [{
      id: "summary-tail", snapshotSequenceNumber: 7,
      publicationSequenceNumber: 7,
      tree: { type: "tree", entries: [["indexes", {
        type: "tree", entries: [["Schema", {
          type: "tree", entries: [["SchemaString", {
            type: "blob", base64: schema,
          }]],
        }]],
      }]] },
    }],
  };
  validateSummaryArtifact(artifact, "javascript", ["summary-tail"]);
  for (const change of [
    (copy) => { copy.target = "erlang"; },
    (copy) => { copy.reference.commit = "stale"; },
    (copy) => { copy.cases = []; },
    (copy) => { copy.cases[0].tree.entries = []; },
    (copy) => {
      copy.cases[0].tree.entries[0][1].entries[0][1].entries[0][1].base64 = "@@";
    },
    (copy) => {
      copy.cases[0].tree.entries[0][1].entries[0][1].entries[0][1].base64 =
        Buffer.from(JSON.stringify({
          trunk: [{ change: [{ data: {} }] }],
        })).toString("base64");
    },
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

test("map reload runner requires the map schema", async () => {
  await assert.rejects(
    runMapReloadMatrix({}, {
      runId: "run",
      profileDigest: "a".repeat(64),
      viewSchema: "object-schema",
      artifactDirectory: "/tmp",
    }),
    /runMapReloadMatrix context requires mapViewSchema/,
  );
});

test("map reload runner returns one row for every writer", async () => {
  const seen = [];
  const result = await runMapReloadMatrix({}, {
    runId: "run",
    profileDigest: "a".repeat(64),
    mapViewSchema: "map-schema",
    artifactDirectory: "/tmp",
  }, {
    runRow: async (_config, _context, writer) => {
      seen.push(writer);
      return structuredClone(mapCells[writer]);
    },
  });

  test("array reload runner requires the array schema and returns every writer row", async () => {
    await assert.rejects(
      runArrayReloadMatrix({}, {
        runId: "run",
        profileDigest: "a".repeat(64),
        artifactDirectory: "/tmp",
      }),
      /runArrayReloadMatrix context requires arrayViewSchema/,
    );
    const seen = [];
    const result = await runArrayReloadMatrix({}, {
      runId: "run",
      profileDigest: "a".repeat(64),
      arrayViewSchema: "array-schema",
      artifactDirectory: "/tmp",
    }, {
      runRow: async (_config, _context, writer) => {
        seen.push(writer);
        return structuredClone(arrayCells[writer]);
      },
    });
    assert.deepEqual(seen, implementations);
    assert.deepEqual(result, arrayCells);
  });
  assert.deepEqual(seen, implementations);
  assert.deepEqual(result, mapCells);
});

test("schema reload matrix requires all nine continued-write cells", () => {
  const matrix = Object.fromEntries(implementations.map((writer) => [
    writer,
    Object.fromEntries(implementations.map((reader) => [
      reader,
      {
        writer,
        reader,
        skipped: false,
        observations: [{
          compatibility: {
            canView: true,
            canUpgrade: false,
            isEquivalent: true,
          },
          openedView: "optional",
          continuedEditing: true,
          peerObservedEdit: true,
          summaryConsumed: true,
          replayedTail: true,
          retainedPeer: true,
          pendingSummaryUsedSequencedSchema: true,
          pendingSummaryVersion: `${writer}-baseline-summary`,
          pendingSummaryPublication: {
            version: `${writer}-baseline-summary`,
            snapshotSequenceNumber: 40,
            publicationSequenceNumber: 41,
          },
          pendingPublicationVerification: {
            checkpoint: {
              wholeTree: { value: { title: `retained-${writer}` } },
              history: { storedSchema: "v1" },
            },
            load: {
              selectedSummaryRequests: [`${writer}-baseline-summary`],
            },
          },
          captureSequencedCheckpoint: {
            wholeTree: { value: { title: `retained-${writer}` } },
            history: { storedSchema: "v1" },
          },
          pendingSummaryReferenceSequenceNumber: 40,
          pendingSummaryCapture: {
            sequenceNumber: 40,
            schema: { content: "\"v1\"" },
            forest: [{ content: "{}" }],
          },
          pendingSummaryInitialCapture: {
            sequenceNumber: 40,
            schema: {
              content: writer === "upstream" ? "\"optional\"" : "\"v1\"",
            },
            forest: [{ content: "{}" }],
          },
          pendingSummaryCaptureSourceBehavior: writer === "upstream"
            ? "upstream-optimistic-encoder-retained-future-state"
            : "stable-reference",
          captureEncoderReference: {
            sequenceNumber: 40,
            schema: { content: "\"v1\"" },
            forest: [{ content: "{}" }],
          },
          retainedEncoderReference: {
            sequenceNumber: 40,
            schema: { content: "\"v1\"" },
            forest: [{ content: "{}" }],
          },
          sequencedEncoderReference: {
            sequenceNumber: 41,
            schema: { content: "\"optional\"" },
            forest: [{ content: "{\"schema\":\"optional\"}" }],
          },
          pendingSummaryBinding: {
            schema: "sequenced-at-capture",
            forest: "sequenced-at-capture",
            captureSequenceNumber: 40,
            upgradeSequenceNumber: 41,
          },
          upgradedSummaryVersion: `${writer}-summary`,
          schemaUpgradeSequenceNumber: 41,
          snapshotSequenceNumber: 42,
          acceptedUpgrade: {
            outerSequenceNumber: 41,
            commits: [{
              revision: `${writer}-upgrade`,
              changeset: [{ schema: { old: "v1", new: "optional" } }],
            }],
          },
          sequencedWriterCheckpoint: {
            sequenceNumber: 41,
            pendingTreeCount: 0,
          },
          retainedPeerAuthor: writer === "upstream" ? "javascript" : "upstream",
          retainedPeerCheckpoint: {
            history: {
              pending: [{
                revision: `${writer}-retained`,
                originatorId: `${writer}-peer-origin`,
                changeset: {
                  changeCount: 1,
                  raw: [{
                    data: {
                      path: ["title"],
                      value: `retained-${writer}`,
                    },
                  }],
                },
              }],
            },
          },
          acceptedRetainedPeer: {
            outerSequenceNumber: 40,
            commits: [{
              revision: `${writer}-retained`,
              originatorId: `${writer}-peer-origin`,
              changeset: [{
                data: { path: ["title"], value: `retained-${writer}` },
              }],
            }],
          },
          pendingWriterInstanceId: `${writer}-writer`,
          pendingWriterCheckpoint: {
            history: {
              pending: [{
                revision: `${writer}-upgrade`,
                changeset: {
                  changeCount: 1,
                  raw: { changes: [{ type: "schema" }] },
                },
              }],
            },
          },
          pendingStoredState: {
            version: `${writer}-baseline-summary`,
            rootTreeId: `${writer}-root-tree`,
            treeIds: [`${writer}-root-tree`, `${writer}-schema-tree`],
            schema: {
              path: ".app/.channels/A/.channels/_C/indexes/Schema/SchemaString",
              id: `${writer}-schema-blob`,
              byteLength: 4,
              hash: "a".repeat(64),
              content: "\"v1\"",
            },
            forest: {
              path: ".app/.channels/A/.channels/_C/indexes/Forest",
              treeId: `${writer}-schema-tree`,
              blobs: [{
                path: ".app/.channels/A/.channels/_C/indexes/Forest/String",
                id: `${writer}-forest-blob`,
                byteLength: 2,
                hash: "b".repeat(64),
                content: "{}",
              }],
            },
          },
          upgradedStoredState: {
            version: `${writer}-summary`,
            rootTreeId: `${writer}-tree`,
            treeIds: [`${writer}-tree`],
            blobIds: [
              `${writer}-upgraded-schema-blob`,
              `${writer}-upgraded-forest-blob`,
            ],
              schema: {
                id: `${writer}-upgraded-schema-blob`,
                content: "\"optional\"",
              },
              forest: {
              blobs: [{
                id: `${writer}-upgraded-forest-blob`,
                content: `{"title":"retained-${writer}"}`,
              }],
            },
          },
          summaryKind: "post-upgrade",
          beforeContinuation: {
            history: {
              pending: [],
              trunk: [
                {
                  revision: `${writer}-retained`,
                  changeset: {
                    changeCount: 1,
                    raw: {
                      changes: [{
                        type: "data",
                        innerChange: {
                          path: ["title"],
                          value: `retained-${writer}`,
                        },
                      }],
                    },
                  },
                },
                {
                  revision: `${writer}-upgrade`,
                  changeset: {
                    changeCount: 1,
                    raw: {
                      changes: [{
                        type: "schema",
                        innerChange: {
                          schema: { old: "v1", new: "optional" },
                        },
                      }],
                    },
                  },
                },
              ],
            },
            wholeTree: {
              value: {
                fields: [[
                  "title",
                  { kind: "string", value: `retained-${writer}` },
                ]],
              },
            },
          },
          freshLoadCheckpoint: {
            history: {
              pending: [],
              trunk: [
                {
                  revision: `${writer}-retained`,
                  changeset: {
                    changeCount: 1,
                    raw: {
                      changes: [{
                        type: "data",
                        innerChange: {
                          path: ["title"],
                          value: `retained-${writer}`,
                        },
                      }],
                    },
                  },
                },
                {
                  revision: `${writer}-upgrade`,
                  changeset: {
                    changeCount: 1,
                    raw: {
                      changes: [{
                        type: "schema",
                        innerChange: {
                          schema: { old: "v1", new: "optional" },
                        },
                      }],
                    },
                  },
                },
              ],
            },
          },
          documentId: `${writer}-document`,
          loadedVersion: `${writer}-summary`,
          selectedSummaryRequests: [`${writer}-summary`],
          selectedSummaryTreeId: `${writer}-tree`,
          selectedTreeRequests: [`${writer}-tree`],
          selectedBlobRequests: reader === "upstream"
            ? [{
              id: `${writer}-upgraded-schema-blob`,
              byteLength: 100,
              hash: "b".repeat(64),
            }]
            : [`${writer}-upgraded-schema-blob`],
          replayStartSequenceNumber: 40,
          replayWatermark: 42,
          replayEvidence: reader === "upstream"
            ? "upstream-delta-storage"
            : "native-handshake",
          readerInstanceId: `${writer}-${reader}-reader`,
        }],
      },
    ])),
  ]));
  assert.equal(validateSchemaReloadResults(matrix), matrix);
  const escapedQuoteHistory = structuredClone(matrix);
  const escapedQuoteChangeset = {
    changeCount: 1,
    raw: 'Changeset([DataChange(Changeset(ChangeData('
      + '2, [], [#("title", OptionalField(FieldChange([], [], '
      + "Some(Replacement(False, Some(Detached(AtomId(None, 0))), "
      + "AtomId(None, 1))))))], [], [], [], "
      + '[Build(AtomId(None, 0), [StringValue("quoted \\"value, still text")])], '
      + "[], [], []), IdentityOrder([]), []))])",
  };
  for (const checkpoint of [
    escapedQuoteHistory.upstream.javascript.observations[0].freshLoadCheckpoint,
    escapedQuoteHistory.upstream.javascript.observations[0].beforeContinuation,
  ]) {
    checkpoint.history.trunk = [
      {
        revision: "escaped-quote",
        changeset: escapedQuoteChangeset,
      },
      checkpoint.history.trunk[1],
    ];
  }
  assert.equal(
    validateSchemaReloadResults(escapedQuoteHistory),
    escapedQuoteHistory,
  );
  const upgradeableEquivalent = structuredClone(matrix);
  for (const row of Object.values(upgradeableEquivalent)) {
    for (const cell of Object.values(row)) {
      cell.observations[0].compatibility.canUpgrade = true;
    }
  }
  assert.equal(
    validateSchemaReloadResults(upgradeableEquivalent),
    upgradeableEquivalent,
  );
  for (const mutate of [
    (copy) => { delete copy.javascript.erlang; },
    (copy) => { copy.erlang.upstream.observations = []; },
    (copy) => { copy.upstream.javascript.skipped = true; },
    (copy) => {
      copy.javascript.upstream.observations[0].continuedEditing = false;
    },
    (copy) => {
      delete copy.upstream.javascript.observations[0].pendingWriterInstanceId;
    },
    (copy) => {
      copy.upstream.javascript.observations[0]
        .pendingWriterCheckpoint.history.pending = [];
    },
    (copy) => {
      copy.upstream.javascript.observations[0].pendingStoredState.version =
        "another-summary";
    },
    (copy) => {
      copy.upstream.javascript.observations[0]
        .pendingStoredState.schema.content = "{\"wrong\":true}";
    },
    (copy) => {
      copy.upstream.javascript.observations[0].acceptedUpgrade.commits = [];
    },
    (copy) => {
      copy.upstream.javascript.observations[0].selectedTreeRequests = [];
    },
    (copy) => {
      copy.upstream.javascript.observations[0].selectedBlobRequests = [];
    },
    (copy) => {
      copy.upstream.javascript.observations[0]
        .retainedPeerCheckpoint.history.pending = [];
    },
    (copy) => {
      copy.upstream.javascript.observations[0]
        .acceptedRetainedPeer.commits[0].changeset = [];
    },
    (copy) => {
      delete copy.upstream.javascript.observations[0].beforeContinuation.history;
    },
    (copy) => {
      copy.upstream.javascript.observations[0].freshLoadCheckpoint.history.trunk = [];
    },
    (copy) => {
      copy.upstream.javascript.observations[0].retainedPeerAuthor = "erlang";
    },
    (copy) => {
      copy.upstream.javascript.observations[0]
        .pendingWriterCheckpoint.history.pending[0] = {
          revision: "wrong-pending",
          changeset: { changeCount: 1, raw: { changes: [{ type: "data" }] } },
        };
    },
    (copy) => {
      copy.upstream.javascript.observations[0].pendingSummaryBinding =
        { schema: "other", forest: "baseline" };
    },
    (copy) => {
      const observation = copy.upstream.javascript.observations[0];
      observation.pendingSummaryCapture =
        structuredClone(observation.sequencedEncoderReference);
      observation.pendingSummaryCapture.sequenceNumber =
        observation.pendingSummaryReferenceSequenceNumber;
      observation.pendingSummaryBinding = {
        schema: "upgrade-sequenced",
        forest: "upgrade-sequenced",
        captureSequenceNumber: 40,
        upgradeSequenceNumber: 41,
      };
    },
    (copy) => {
      copy.upstream.javascript.observations[0].selectedTreeRequests =
        ["unrelated-tree"];
    },
    (copy) => {
      copy.upstream.javascript.observations[0].selectedBlobRequests =
        ["unrelated-blob"];
    },
  ]) {
    const copy = structuredClone(matrix);
    mutate(copy);
    assert.throws(() => validateSchemaReloadResults(copy));
  }
});

test("schema reload runner executes one row for every writer", async () => {
  const seen = [];
  const result = await runSchemaReloadMatrix({}, {}, {
    runRow: async (_config, _context, writer) => {
      seen.push(writer);
      return { writer };
    },
  });
  assert.deepEqual(seen, implementations);
  assert.deepEqual(result, {
    upstream: { writer: "upstream" },
    javascript: { writer: "javascript" },
    erlang: { writer: "erlang" },
  });
});
