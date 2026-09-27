import assert from "node:assert/strict";
import { test } from "node:test";
import {
  loadRequests, mapEntryMatches, readCell, runArtifactInterop, runMapReloadMatrix,
  runReloadMatrix, runSchemaReloadMatrix, validateMapResults, validateResults,
  validateSchemaReloadResults, validateSummaryArtifact,
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
    selectedTreeRequests: ["tree"],
    selectedBlobRequests: ["blob"],
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
      + "[], []), IdentityOrder([])))])",
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
