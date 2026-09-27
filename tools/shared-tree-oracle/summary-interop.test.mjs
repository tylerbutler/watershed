import assert from "node:assert/strict";
import { test } from "node:test";
import {
  continueArrayReader,
  loadRequests, mapEntryMatches, readCell, runArrayReloadMatrix, runArtifactInterop,
  restoreArrayReader,
  runMapReloadMatrix, runReloadMatrix, validateArrayResults, validateMapResults,
  validateResults, validateSummaryArtifact,
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
