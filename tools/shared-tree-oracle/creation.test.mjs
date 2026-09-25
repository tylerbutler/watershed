import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rm, unlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import {
  inspectCreationSummary,
  runCreationCommand,
  validateCreationCapture,
  validateCreationInteropEvidence,
  validateCreationInteropReport,
} from "./creation.mjs";
import { observedDocumentServiceFactory } from "./service.mjs";

function blob(content) {
  return { type: 2, content: JSON.stringify(content) };
}

function tree(entries) {
  return { type: 1, tree: entries };
}

function combinedSummary() {
  return tree({
    ".protocol": tree({
      attributes: blob({ minimumSequenceNumber: 0, sequenceNumber: 0 }),
      quorumMembers: blob([]),
      quorumProposals: blob([]),
      quorumValues: blob([["code", {
        key: "code",
        value: { package: "watershed-shared-tree" },
        approvalSequenceNumber: 0,
        commitSequenceNumber: 0,
        sequenceNumber: 0,
      }]]),
    }),
    ".app": tree({
      ".metadata": blob({
        createContainerRuntimeVersion: "3.1.0",
        summaryNumber: 1,
        summaryFormatVersion: 1,
        gcFeature: 3,
        sessionExpiryTimeoutMs: 2_592_000_000,
        sweepEnabled: false,
        tombstoneTimeoutMs: 3_110_400_000,
        message: { sequenceNumber: -1 },
        documentSchema: {
          version: 1,
          refSeq: 0,
          info: { minVersionForCollab: "2.117.0" },
          runtime: {
            explicitSchemaControl: true,
            idCompressorMode: "on",
            opGroupingEnabled: true,
          },
        },
      }),
      ".idCompressor": blob(
        "AAAAAAAAAEAAAAAAAAAAAAAAAAAAAPA/AAAAAAAA8D9M8staEmEhaqAPn3ijLvkCAAAAAAAAAAAAAAAAAAiAQAAAAAAAAPA/",
      ),
      ".aliases": blob([["root", "A"]]),
      ".channels": tree({
        A: tree({
          ".component": blob({
            pkg: "[\"org.watershed.shared-tree.m1.bootstrap\"]",
            summaryFormatVersion: 2,
            isRootDataStore: true,
          }),
          ".channels": tree({
            root: tree({
              header: blob({
                blobs: [],
                content: {
                  tree: {
                    type: "Plain",
                    value: { type: "__fluid_handle__", url: "/A/_C" },
                  },
                },
              }),
              ".attributes": blob({
                type: "https://graph.microsoft.com/types/map",
                snapshotFormatVersion: "0.2",
                packageVersion: "3.1.0",
              }),
            }),
            _C: tree({
              ".metadata": blob({ version: 2 }),
              ".attributes": blob({
                type: "https://graph.microsoft.com/types/tree",
                snapshotFormatVersion: "0.0.0",
                packageVersion: "3.1.0",
              }),
              indexes: tree({
                EditManager: tree({
                  ".metadata": blob({ version: 2 }),
                  String: blob({ trunk: [], branches: [], version: 7 }),
                }),
                Schema: tree({
                  ".metadata": blob({ version: 2 }),
                  SchemaString: blob({ version: 2, nodes: {}, root: {} }),
                }),
                Forest: tree({
                  ".metadata": blob({ version: 2 }),
                  contents: blob({ version: 2, data: [] }),
                }),
                DetachedFieldIndex: tree({
                  ".metadata": blob({ version: 2 }),
                  DetachedFieldIndexBlob: blob({ version: 2, data: [], maxId: 0 }),
                }),
              }),
            }),
          }),
        }),
      }),
    }),
  });
}

function completeCapture() {
  const capture = inspectCreationSummary(combinedSummary(), {
    documentId: "assigned-document",
    freshReaderLoaded: true,
    freshReaderContinuedEditing: true,
  });
  capture.createResponse = { documentId: "assigned-document" };
  capture.persistedInitialSummary = {
    version: { id: "summary", treeId: "tree" },
    sequenceNumber: 0,
    minimumSequenceNumber: 0,
    paths: ["/.app", "/.channels", "/.protocol", "/.protocol/attributes"],
    snapshot: { tree: {}, blobs: {}, blobEncoding: "base64" },
  };
  capture.freshLoad = {
    initialRoot: {
      title: "",
      enabled: false,
      rating: 0,
      marker: null,
      note: null,
      point: { x: 0, y: 0 },
    },
    continuedRoot: {
      title: "creation-continuation",
      enabled: false,
      rating: 0,
      marker: null,
      note: null,
      point: { x: 0, y: 0 },
    },
    storageObservations: [{
      operation: "readMessages",
      done: true,
      sequenceNumbers: [],
    }],
    initialSummaryRemainedHeadAfterEdit: true,
  };
  return capture;
}

function completeInteropReport() {
  const runId = "creation-run";
  const profileDigest =
    "53e73c5359c5940c410c98f68eb1e4928817f7e1296f96c778aa48c0ecf2934b";
  return {
    formatVersion: 1,
    runId,
    profileDigest,
    service: {
      implementation: "floodgate",
      revision: "0eb493fc46d1bb9baf1151a6ccdde93544e057e7",
      simulated: false,
    },
    cells: ["javascript", "erlang"].flatMap((creator) =>
      ["javascript", "erlang", "upstream"].map((reader) => ({
        creator,
        reader,
        runId,
        profileDigest,
        documentId: `${creator}-document`,
        nativeCreated: true,
        loadedInitialSummary: true,
        continuedEditing: true,
        peerObservedEdit: true,
        reloadedSummaryAndTail: true,
        evidence: {
          creation: `${creator}/creation.json`,
          initialLoad: `${creator}/${reader}/initial-load.json`,
          continuation: `${creator}/${reader}/continuation.json`,
          summaryReload: `${creator}/${reader}/summary-reload.json`,
          upstreamContinuation:
            `${creator}/${reader}/upstream-summary-continuation.json`,
        },
      }))),
    skipped: [],
    divergences: [],
  };
}

function matrixTree(creator, {
  title = "native creation",
  enabled = true,
  rating = 17.5,
  note,
  point = { x: 3, y: -4 },
} = {}) {
  return {
    present: true,
    value: {
      kind: "object",
      schemaId: "org.watershed.shared-tree.m1.Root",
      fields: [
        ["enabled", { kind: "boolean", value: enabled }],
        ["marker", { kind: "null" }],
        ...(note === undefined ? [] : [["note", { kind: "string", value: note }]]),
        ["point", {
          kind: "object",
          schemaId: "org.watershed.shared-tree.m1.Point",
          fields: [
            ["x", { kind: "number", value: point.x }],
            ["y", { kind: "number", value: point.y }],
          ],
        }],
        ["rating", { kind: "number", value: rating }],
        ["title", { kind: "string", value: title }],
      ],
    },
  };
}

async function writeInteropEvidence(directory, report) {
  const write = async (relative, value) => {
    const path = join(directory, relative);
    await mkdir(join(path, ".."), { recursive: true });
    await writeFile(path, `${JSON.stringify(value)}\n`);
  };
  for (const creator of ["javascript", "erlang"]) {
    const cell = report.cells.find((item) => item.creator === creator);
    const common = {
      formatVersion: 1,
      runId: report.runId,
      profileDigest: report.profileDigest,
      creator,
      documentId: cell.documentId,
    };
    await write(`${creator}/creation.json`, {
      ...common,
      kind: "creation",
      readers: ["javascript", "erlang", "upstream"],
      nativeCreated: true,
      root: matrixTree(creator).value,
    });
    const rating = creator === "javascript" ? 31 : 32;
    const stages = [
      ["all-authors", matrixTree(creator, {
        title: `${creator}-upstream`, enabled: false, rating,
      })],
      ["optional-set", matrixTree(creator, {
        title: `${creator}-upstream`, enabled: false, rating,
        note: `${creator}-optional`,
      })],
      ["optional-clear", matrixTree(creator, {
        title: `${creator}-upstream`, enabled: false, rating,
      })],
      ["nested-edit", matrixTree(creator, {
        title: `${creator}-upstream`, enabled: false, rating,
        point: { x: 8, y: -4 },
      })],
      ["parent-replacement", matrixTree(creator, {
        title: `${creator}-upstream`, enabled: false, rating,
        point: { x: 13, y: 21 },
      })],
      ["conflict", matrixTree(creator, {
        title: `${creator}-erlang-conflict`, enabled: false, rating,
        point: { x: 13, y: 21 },
      })],
    ];
    for (const reader of ["javascript", "erlang", "upstream"]) {
      const binding = { ...common, reader };
      const initial = matrixTree(creator);
      const tail = matrixTree(creator, {
        title: `${creator}-erlang-conflict`, enabled: false, rating,
        note: `${creator}-after-native-summary`,
        point: { x: 13, y: 21 },
      });
      await write(`${creator}/${reader}/initial-load.json`, {
        ...binding,
        kind: "initial-load",
        stored: {
          sequenceNumber: 0,
          minimumSequenceNumber: 0,
          aliases: [["root", "A"]],
          bootstrapHandle: "/A/_C",
        },
        observation: {
          implementation: reader,
          sequenceNumber: 3,
          pendingTreeCount: 0,
          inflightSubmissionCount: 0,
          wholeTree: initial,
        },
      });
      await write(`${creator}/${reader}/continuation.json`, {
        ...binding,
        kind: "continuation",
        conflictWinner: `${creator}-erlang-conflict`,
        stages: stages.map(([name, wholeTree], index) => ({
          name,
          observation: {
            implementation: reader,
            sequenceNumber: 4 + index,
            pendingTreeCount: 0,
            inflightSubmissionCount: 0,
            wholeTree,
          },
        })),
        firstEditAllocations: [{ allocations: [{ first: 1, last: 1 }] }],
      });
      await write(`${creator}/${reader}/summary-reload.json`, {
        ...binding,
        kind: "summary-reload",
        version: `${creator}-native-summary`,
        nativeSummaryReferenceSequenceNumber: 10,
        tailSequenceNumber: 11,
        tailSubmission: { outerSequenceNumber: 11 },
        expectedTree: tail,
        reloaded: {
          author: reader,
          observation: {
            implementation: reader,
            sequenceNumber: 11,
            pendingTreeCount: 0,
            inflightSubmissionCount: 0,
            wholeTree: tail,
          },
          selectedSummaryRequests: [{
            path: `/git/commits/${creator}-native-summary`,
          }],
        },
      });
      await write(`${creator}/${reader}/upstream-summary-continuation.json`, {
        ...binding,
        kind: "upstream-summary-continuation",
        upstreamSummary: {
          summaryAckOp: {
            sequenceNumber: 12,
            contents: { handle: `${creator}-upstream-summary` },
          },
        },
        observation: {
          implementation: reader,
          sequenceNumber: 13,
          pendingTreeCount: 0,
          inflightSubmissionCount: 0,
          wholeTree: matrixTree(creator, {
            title: `${creator}-after-upstream-summary`,
            enabled: false,
            rating,
            note: `${creator}-after-native-summary`,
            point: { x: 13, y: 21 },
          }),
        },
      });
    }
  }
}

async function evidenceFixture(t) {
  const directory = await mkdtemp(join(tmpdir(), "watershed-creation-evidence-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const report = completeInteropReport();
  await writeInteropEvidence(directory, report);
  return { directory, report };
}

test("create observation records only the combined summary and assigned document ID", async () => {
  const summary = combinedSummary();
  const service = {
    resolvedUrl: {
      id: "assigned-document",
      tokens: { jwt: "must-not-be-captured" },
    },
  };
  const factory = {
    async createContainer(actual) {
      assert.equal(actual, summary);
      return service;
    },
  };
  const observations = [];
  const wrapped = observedDocumentServiceFactory(
    factory,
    observations,
    { observeCreateContainer: true },
  );

  assert.equal(
    await wrapped.createContainer(summary, { tokens: { jwt: "request-secret" } }),
    service,
  );
  assert.deepEqual(observations, [{
    operation: "createContainer",
    summary,
    documentId: "assigned-document",
  }]);
  assert(!JSON.stringify(observations).includes("secret"));
});

test("creation inspection derives the C1 contract and pinned POST payload", () => {
  const capture = inspectCreationSummary(combinedSummary(), {
    documentId: "assigned-document",
    freshReaderLoaded: true,
    freshReaderContinuedEditing: true,
  });

  assert.equal(capture.sequenceNumber, 0);
  assert.equal(capture.minimumSequenceNumber, 0);
  assert.deepEqual(capture.aliases, [["root", "A"]]);
  assert.equal(capture.bootstrapHandle, "/A/_C");
  assert.equal(capture.codePackage, "watershed-shared-tree");
  assert.equal(capture.idCompressorMode, "on");
  assert.deepEqual(capture.history, { trunk: [], branches: [] });
  assert.equal(capture.historyCodecVersion, 7);
  assert.equal(capture.freshReaderLoaded, true);
  assert.equal(capture.freshReaderContinuedEditing, true);
  assert.deepEqual(capture.codeQuorum, {
    approvalSequenceNumber: 0,
    commitSequenceNumber: 0,
    sequenceNumber: 0,
  });
  assert.deepEqual(capture.gc, {
    feature: 3,
    treePresent: false,
    nodes: null,
  });
  assert.deepEqual(capture.compressor, {
    encoding: "base64",
    byteLength: 72,
    hash: "c216d2a40cef7c59ff943b202a965ee6ff814a3daaf92c863d1d6a8915623f67",
    version: 2,
    hasLocalState: false,
    sessionCount: 1,
    clusterCount: 1,
    clusters: [{ sessionIndex: 0, capacity: 513, count: 1 }],
  });
  assert.deepEqual(capture.emptyCompressorContract, {
    serialized: "AAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
    encoding: "base64",
    byteLength: 32,
    hash: "497d0d90f9a77f1d67f0567e67f7ed60f9d324cde0db266e51afd4b25cf24fa4",
    version: 2,
    hasLocalState: false,
    sessionCount: 0,
    clusterCount: 0,
    clusters: [],
  });
  assert.deepEqual(capture.routes, {
    dataStore: "/A",
    map: "/A/root",
    tree: "/A/_C",
  });
  assert.equal(capture.dataStoreType, "org.watershed.shared-tree.m1.bootstrap");
  assert.equal(capture.metadata.lastMessage, undefined);
  assert.deepEqual(capture.metadata.message, { sequenceNumber: -1 });
  assert.deepEqual(capture.treeState.history, {
    trunk: [],
    branches: [],
    version: 7,
  });
  assert.deepEqual(capture.treeState.detachedFields, {
    version: 2,
    data: [],
    maxId: 0,
  });
  assert.equal(capture.createPayload.sequenceNumber, 0);
  assert.deepEqual(
    capture.createPayload.values,
    JSON.parse(combinedSummary().tree[".protocol"].tree.quorumValues.content),
  );
  assert.deepEqual(capture.createPayload.summary.entries.map(({ path }) => path).sort(), [
    ".aliases",
    ".channels",
    ".idCompressor",
    ".metadata",
  ]);
  assert(!capture.createPayload.summary.entries.some(({ path }) => path === ".app"));
  assert.equal(capture.initialCombinedSummary.tree[".app"].type, 1);
  validateCreationCapture(completeCapture());
});

test("creation validation rejects unmeasured or incompatible contract fields", () => {
  const capture = completeCapture();
  for (const mutate of [
    (value) => { value.sequenceNumber = 1; },
    (value) => { value.minimumSequenceNumber = 1; },
    (value) => { value.aliases = []; },
    (value) => { value.bootstrapHandle = "/wrong"; },
    (value) => { value.codePackage = "watershed-tree-oracle"; },
    (value) => { value.idCompressorMode = "off"; },
    (value) => { value.history.trunk.push({}); },
    (value) => { value.freshReaderLoaded = false; },
    (value) => { value.freshReaderContinuedEditing = false; },
    (value) => { value.createPayload.summary.entries.push({ path: ".app" }); },
    (value) => { value.createResponse.documentId = "different-document"; },
    (value) => { value.persistedInitialSummary.sequenceNumber = 1; },
    (value) => { value.freshLoad.initialSummaryRemainedHeadAfterEdit = false; },
    (value) => { value.freshLoad.storageObservations[0].sequenceNumbers = [1]; },
  ]) {
    const changed = structuredClone(capture);
    mutate(changed);
    assert.throws(() => validateCreationCapture(changed));
  }
});

test("capture command publishes one credential-free artifact", async (t) => {
  const output = await mkdtemp(join(tmpdir(), "watershed-creation-test-"));
  t.after(() => rm(output, { recursive: true, force: true }));
  const capture = completeCapture();

  const result = await runCreationCommand(["capture", "--output", output], {
    capture: async () => capture,
    serviceConfig: () => ({ secret: "must-not-be-written" }),
  });

  assert.equal(result, capture);
  const artifact = JSON.parse(await readFile(join(output, "capture.json"), "utf8"));
  assert.deepEqual(artifact, JSON.parse(JSON.stringify(capture)));
  assert(!JSON.stringify(artifact).includes("must-not-be-written"));
});

test("creation interop report requires the strict six-cell matrix", () => {
  const report = completeInteropReport();

  assert.equal(validateCreationInteropReport(report), report);
});

test("creation interop report rejects duplicate cells", () => {
  const report = completeInteropReport();
  report.cells[1] = structuredClone(report.cells[0]);

  assert.throws(() => validateCreationInteropReport(report), /duplicate|six-cell/i);
});

test("creation interop report rejects another run or profile", () => {
  for (const mutate of [
    (report) => { report.cells[0].runId = "another-run"; },
    (report) => { report.cells[0].profileDigest = "0".repeat(64); },
    (report) => { report.cells[0].documentId = "erlang-document"; },
  ]) {
    const report = completeInteropReport();
    mutate(report);
    assert.throws(() => validateCreationInteropReport(report), /run|profile|document/i);
  }
});

test("creation interop report rejects missing evidence", () => {
  const report = completeInteropReport();
  delete report.cells[0].evidence.summaryReload;

  assert.throws(() => validateCreationInteropReport(report), /evidence/i);
});

test("creation interop report rejects absent targets", () => {
  const report = completeInteropReport();
  report.cells = report.cells.filter(({ reader }) => reader !== "erlang");

  assert.throws(() => validateCreationInteropReport(report), /six-cell|target/i);
});

test("creation interop report rejects a simulated service", () => {
  const report = completeInteropReport();
  report.service.simulated = true;

  assert.throws(() => validateCreationInteropReport(report), /simulated|service/i);
});

test("creation interop evidence validates linked artifacts", async (t) => {
  const { directory, report } = await evidenceFixture(t);

  assert.equal(await validateCreationInteropEvidence(report, directory), report);
});

test("creation interop evidence rejects nonexistent artifacts", async (t) => {
  const { directory, report } = await evidenceFixture(t);
  await unlink(join(directory, report.cells[0].evidence.initialLoad));

  await assert.rejects(
    validateCreationInteropEvidence(report, directory),
    /evidence|initial-load|ENOENT/i,
  );
});

test("creation interop evidence rejects stale run and profile IDs", async (t) => {
  for (const field of ["runId", "profileDigest"]) {
    const { directory, report } = await evidenceFixture(t);
    const path = join(directory, report.cells[0].evidence.continuation);
    const artifact = JSON.parse(await readFile(path, "utf8"));
    artifact[field] = field === "runId" ? "stale-run" : "0".repeat(64);
    await writeFile(path, JSON.stringify(artifact));

    await assert.rejects(
      validateCreationInteropEvidence(report, directory),
      /run|profile/i,
    );
  }
});

test("creation interop evidence rejects wrong document and reader", async (t) => {
  for (const field of ["documentId", "reader"]) {
    const { directory, report } = await evidenceFixture(t);
    const path = join(directory, report.cells[0].evidence.summaryReload);
    const artifact = JSON.parse(await readFile(path, "utf8"));
    artifact[field] = field === "documentId" ? "wrong-document" : "erlang";
    await writeFile(path, JSON.stringify(artifact));

    await assert.rejects(
      validateCreationInteropEvidence(report, directory),
      /document|reader/i,
    );
  }
});

test("creation interop evidence rejects corrupt JSON", async (t) => {
  const { directory, report } = await evidenceFixture(t);
  await writeFile(join(directory, report.cells[0].evidence.upstreamContinuation), "{");

  await assert.rejects(
    validateCreationInteropEvidence(report, directory),
    /JSON|evidence|upstream/i,
  );
});

test("creation interop evidence rejects contradictory report booleans", async (t) => {
  const { directory, report } = await evidenceFixture(t);
  const path = join(directory, report.cells[0].evidence.initialLoad);
  const artifact = JSON.parse(await readFile(path, "utf8"));
  artifact.stored.sequenceNumber = 1;
  await writeFile(path, JSON.stringify(artifact));

  await assert.rejects(
    validateCreationInteropEvidence(report, directory),
    /initial summary|initial-load|sequence/i,
  );
});

test("creation interop evidence rejects no-op requested edits", async (t) => {
  const { directory, report } = await evidenceFixture(t);
  const path = join(directory, report.cells[0].evidence.continuation);
  const artifact = JSON.parse(await readFile(path, "utf8"));
  artifact.stages[0].observation.wholeTree =
    matrixTree("javascript", { enabled: false });
  await writeFile(path, JSON.stringify(artifact));

  await assert.rejects(
    validateCreationInteropEvidence(report, directory),
    /all-authors|another tree/i,
  );
});

test("creation interop evidence rejects a tail before the native summary", async (t) => {
  const { directory, report } = await evidenceFixture(t);
  const path = join(directory, report.cells[0].evidence.summaryReload);
  const artifact = JSON.parse(await readFile(path, "utf8"));
  artifact.tailSequenceNumber = artifact.nativeSummaryReferenceSequenceNumber;
  artifact.tailSubmission.outerSequenceNumber = artifact.tailSequenceNumber;
  await writeFile(path, JSON.stringify(artifact));

  await assert.rejects(
    validateCreationInteropEvidence(report, directory),
    /tail|native summary/i,
  );
});
