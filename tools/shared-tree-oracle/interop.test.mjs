import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";
import * as interop from "./interop.mjs";
import { caseIds, transactionCaseIds } from "./client-interop.mjs";
import {
  assertPreflightProfile,
  corpusCommand,
  createArtifactEvidence,
  failureDiagnostic,
  loadInteropProfile,
  parseTestCount,
  parseInteropOptions,
  runInteropCommand,
  validateInteropReport,
} from "./interop.mjs";
import {
  generateSchedules,
  identifierPairCells,
  requiredFailureCells,
  requiredSchemaRaceCells,
  requiredScenarioCells,
  transactionConstraintCells,
  transactionPairCells,
  writeSeededFailure,
} from "./interop-scenarios.mjs";

const oracleDirectory = resolve(import.meta.dirname);
const repository = resolve(oracleDirectory, "../..");
const profilePath = join(repository, "test/fixtures/shared_tree/profile.json");
const reference = {
  package: "@fluidframework/tree",
  version: "3.1.0",
  commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
};
const service = {
  implementation: "floodgate",
  revision: "0eb493fc46d1bb9baf1151a6ccdde93544e057e7",
};
const implementations = ["upstream", "javascript", "erlang"];

test("corpus commands select SharedTree test files and cannot use function filters", () => {
  assert.deepEqual(corpusCommand("erlang"),
    ["test", "--target", "erlang", "--", "shared_tree"]);
  assert.deepEqual(corpusCommand("javascript"),
    ["test", "--target", "javascript", "--", "shared_tree"]);
});

test("coordinator failure diagnostics retain artifact and cleanup errors", () => {
  const cause = {
    code: "facade-error",
    operation: "array-insert",
    message: "identifier field is absent",
  };
  const error = Object.assign(new Error("primary failure"), {
    code: "PRIMARY",
    cause,
    artifactCaptureError: Object.assign(new Error("artifact write failed"), {
      code: "ENOTDIR",
    }),
    cleanupErrors: [
      Object.assign(new Error("client close failed"), { code: "ECONNRESET" }),
      new Error("container dispose failed"),
    ],
  });
  assert.deepEqual(failureDiagnostic(error), {
    name: "Error",
    message: "primary failure",
    code: "PRIMARY",
    stack: error.stack,
    cause,
    artifactCaptureError: {
      name: "Error",
      message: "artifact write failed",
      code: "ENOTDIR",
      stack: error.artifactCaptureError.stack,
    },
    cleanupErrors: [
      {
        name: "Error",
        message: "client close failed",
        code: "ECONNRESET",
        stack: error.cleanupErrors[0].stack,
      },
      {
        name: "Error",
        message: "container dispose failed",
        stack: error.cleanupErrors[1].stack,
      },
    ],
  });
});

test("failed status publication preserves the primary coordinator failure", async () => {
  const directory = await mkdtemp(join(tmpdir(), "watershed-status-failure-"));
  await mkdir(join(directory, "status.json.tmp"));
  const primary = Object.assign(new Error("primary acceptance failure"), {
    code: "PRIMARY",
  });

  await assert.rejects(() => interop.recordAcceptanceFailure({
    runDirectory: directory,
    error: primary,
    runId: "status-failure-run",
    profileDigest: "profile-digest",
  }), (error) => error === primary);

  assert(primary.statusPublicationError instanceof Error);
  const artifact = JSON.parse(await readFile(primary.failurePath, "utf8"));
  assert.equal(artifact.kind, "coordinator-failure");
  assert.equal(artifact.error.message, "primary acceptance failure");
  assert.equal(artifact.error.code, "PRIMARY");
});

test("failed status publication preserves a frozen primary error", async () => {
  const directory = await mkdtemp(join(tmpdir(), "watershed-frozen-failure-"));
  await mkdir(join(directory, "status.json.tmp"));
  const primary = Object.freeze(new Error("frozen primary failure"));

  await assert.rejects(() => interop.recordAcceptanceFailure({
    runDirectory: directory,
    error: primary,
    runId: "frozen-failure-run",
    profileDigest: "profile-digest",
  }), (error) => error === primary);

  const artifact = JSON.parse(
    await readFile(join(directory, "failure.json"), "utf8"),
  );
  assert.equal(artifact.error.message, "frozen primary failure");
});

function observations(prefix, sequenceNumber, pendingTreeCount = 0) {
  return implementations.map((implementation) => ({
    implementation,
    instanceId: `${prefix}-${implementation}`,
    sequenceNumber,
    pendingTreeCount,
    inflightSubmissionCount: pendingTreeCount,
    wholeTree: {
      schemaId: "org.watershed.shared-tree.m1.Root",
      fields: { title: `${prefix}-${sequenceNumber}` },
    },
    ...(implementation === "upstream" ? {} : { reconnectRetries: [] }),
  }));
}

function deterministicEvidence(cell) {
  const orderedAuthors = cell.order == null
    ? cell.authors
    : [
      cell.order.slice(0, -"-first".length),
      ...cell.authors.filter((author) =>
        author !== cell.order.slice(0, -"-first".length)),
    ];
  const submissions = orderedAuthors.map((author, index) => ({
    author,
    outerSequenceNumber: 9 + index,
    innerIndex: 0,
    referenceSequenceNumber: 8,
    batchId: `${cell.id}-batch-${index}`,
    revision: index,
    originatorId: `${cell.id}-origin-${index}`,
    allocations: [{
      sessionId: `${cell.id}-session-${index}`,
      first: 0,
      last: 3,
    }],
  }));
  const evidence = {
    authoredPrefixes: cell.authors.map((author) => ({
      author,
      referenceSequenceNumber: 8,
    })),
    submissions,
    notifications: {
      intermediateLocalAuthors: [...cell.authors],
      settledRemoteObservers: implementations.filter(
        (implementation) => !cell.authors.includes(implementation),
      ),
    },
  };
  if (cell.family === "grouped-commits") {
    const commitCount = cell.authors[0] === "upstream" ? 3 : 1;
    const allocations = [{
      sessionId: `${cell.id}-group-session`,
      first: 0,
      last: 8,
    }];
    const commits = Array.from({ length: commitCount }, (_value, index) => ({
      innerIndex: index + allocations.length,
      revision: index,
      originatorId: cell.authors[0],
    }));
    evidence.grouped = {
      outerSequenceNumber: 12,
      commits,
      allocations,
    };
    evidence.submissions = commits.map((commit) => ({
      author: cell.authors[0],
      outerSequenceNumber: 12,
      innerIndex: commit.innerIndex,
      referenceSequenceNumber: 8,
      ...(cell.authors[0] === "upstream"
        ? {}
        : { batchId: `${cell.id}-batch` }),
      revision: commit.revision,
      originatorId: commit.originatorId,
      allocations,
    }));
  }
  if (["parent-replacement-child-edit", "detached-child-reconciliation"]
    .includes(cell.family)) {
    evidence.retained = {
      upstreamReference: { before: { x: 1, y: 2 }, after: { x: 42, y: 2 } },
      removed: [{ x: 42, y: 2 }],
      refreshers: [[1, 2], [42, 2]],
      summaryConsumed: true,
      continuationObserved: true,
    };
  }
  if (cell.family === "delivery-duplicates-gaps") {
    evidence.delivery = {
      heldSequenceNumbers: [10, 11],
      deliveredSequenceNumbers: [11, 10, 10],
      duplicateSequenceNumber: 10,
      gapRepairObserved: true,
      duplicateInvalidations: 0,
      duplicateAllocations: 0,
    };
  }
  if (cell.family === "multi-session-ids") {
    evidence.sessions = implementations.map((implementation, index) => ({
      implementation,
      before: `${cell.id}-before-${index}`,
      after: `${cell.id}-after-${index}`,
      restored: `${cell.id}-before-${index}`,
      restoredAfter: `${cell.id}-before-${index}`,
    }));
  }
  if (cell.profile === "array") {
    const deleted = ["array-insert-remove", "array-overlapping-remove"]
      .includes(cell.family)
      || (cell.family === "array-move-delete"
        && cell.order !== `${cell.authors[1]}-first`);
    evidence.array = {
      finalTree: { present: true, value: { kind: "object", fields: [] } },
      retainedObjectReferences: [!deleted, !deleted],
      childEditObserved: ["array-move-child-edit", "array-summary-tail"]
        .includes(cell.family),
    };
  }
  return evidence;
}

function measuredPayload(item) {
  return {
    id: item.id,
    documentId: item.documentId,
    instanceIds: item.instanceIds,
    authorCoverage: item.authorCoverage,
    checkpoints: item.checkpoints,
    evidence: item.evidence,
  };
}

function reloadMeasuredPayload(item) {
  return Object.fromEntries(Object.entries(item)
    .filter(([name]) => name !== "artifacts"));
}

function measured(prefix, cell, artifact) {
  const authors = cell.authors;
  return {
    runId: "current",
    profileDigest: "set-by-builder",
    documentId: `document-${prefix}`,
    instanceIds: Object.fromEntries(implementations.map((implementation) =>
      [implementation, `${prefix}-${implementation}`])),
    authorCoverage: [...authors],
    checkpoints: [
      {
        label: "initial",
        stage: "quiescent",
        observations: observations(prefix, 6),
      },
      {
        label: "optimistic",
        stage: "intermediate",
        observations: observations(prefix, 8, 1),
      },
      {
        label: "settled",
        stage: "quiescent",
        observations: observations(prefix, 12),
      },
    ],
    evidence: deterministicEvidence(cell),
    artifacts: [artifact],
    passed: true,
    skipped: false,
  };
}

async function validFixture() {
  const owned = await mkdtemp(join(tmpdir(), "watershed-interop-test-"));
  await mkdir(join(owned, "evidence"));
  const loaded = await loadInteropProfile(profilePath);
  const artifactFiles = new Map();
  function artifact(kind, subject, documentId, extra = {}) {
    const name = `${kind}-${subject}`.replace(/[^a-z0-9.-]+/gi, "_");
    const reference = `evidence/${name}.json`;
    artifactFiles.set(reference, {
      formatVersion: 1,
      runId: "current",
      profileDigest: loaded.profileDigest,
      kind,
      subject,
      documentId,
      ...extra,
    });
    return reference;
  }
  const rawGates = () => ({
    raw: {
      gates: {
        javascript: { reconnectRetries: [] },
        erlang: { reconnectRetries: [] },
      },
    },
  });
  const deterministic = requiredScenarioCells().map((cell, index) => {
    const prefix = `deterministic-${index}`;
    const item = {
      ...cell,
      ...measured(prefix, cell, undefined),
    };
    item.artifacts = [artifact(
      "deterministic",
      cell.id,
      item.documentId,
      { measured: measuredPayload(item), ...rawGates() },
    )];
    return item;
  });
  const reconnect = implementations.slice(1).flatMap((target) =>
    caseIds.map((caseId, index) => {
      const subject = `${target}:${caseId}`;
      const documentId = `reconnect-${subject}`;
      return {
        target,
        caseId,
        runId: "current",
        profileDigest: loaded.profileDigest,
        profile: "fluid-3.1.0-fixed-object",
        documentId,
        passed: true,
        skipped: false,
        evidence: {
          sequenceNumber: 20,
          clientId: `${target}-${caseId}`,
          pendingTreeCount: 0,
          checkpoints: ["initial", "intermediate", "final"].map((label) => ({
            label,
            sequenceNumber: 20,
            clientId: `${target}-${caseId}`,
            pendingTreeCount: 0,
            values: {},
            events: [],
          })),
          submissions: [{
            sequenceNumber: 20,
            batchId: `${target}-${index}`,
            revision: index,
            originatorId: target,
          }],
          artifacts: [artifact("reconnect", subject, documentId)],
          ...(caseId === "detached-repair"
            ? { repairValues: [[1, 2], [42, 2]] }
            : {}),
        },
      };
    }));
  const failures = requiredFailureCells().map((cell) => ({
    ...cell,
    runId: "current",
    profileDigest: loaded.profileDigest,
    documentId: `failure-${cell.id}`,
    outcome: "refused",
    stage: cell.expectedStage,
    typedError: {
      code: cell.errorCode,
      operation: cell.errorOperation,
      message: cell.diagnosticTerms.join(" "),
    },
    clientState: cell.clientState,
    partialMutationObserved: false,
    unrelatedDocumentPassed: true,
    artifacts: [artifact("failure", cell.id, `failure-${cell.id}`)],
    ...(cell.kind === "local-refusal" ? {
      before: { root: { title: "" }, pendingTreeCount: 0 },
      after: { root: { title: "" }, pendingTreeCount: 0, events: [] },
      outboundTreeMessages: 0,
      continuationPeerObserved: true,
      writableTreeExposedAfterRefusal: true,
    } : {
      writableTreeExposedAfterRefusal: false,
    }),
  }));
  const seeded = generateSchedules({ seed: 42, iterations: 300 })
    .map((schedule, index) => {
    const prefix = `seeded-${index}`;
    const item = {
      ...schedule,
      ...measured(prefix, {
        id: String(index),
        family: "seeded",
        authors: implementations,
      }, undefined),
      identityMapping: Object.fromEntries(implementations.map((implementation) => [
        implementation,
        {
          instanceId: `${prefix}-${implementation}`,
          clientIds: [`${prefix}-${implementation}-client`],
          originatorIds: [`${prefix}-${implementation}-origin`],
          revisions: [index],
          sessionIds: [`${prefix}-${implementation}-session`],
        },
      ])),
      summaries: schedule.actions
        .filter(({ type }) => type === "summarize")
        .map(({ author }) => ({ author, result: { version: `${prefix}-version` } })),
      reloads: schedule.actions
        .filter(({ type }) => type === "reload")
        .map(({ author }) => ({
          author,
          instanceId: `${prefix}-${author}-fresh`,
          observation: { wholeTree: { schemaId: "Root" } },
          selectedSummaryRequests: [],
        })),
      schemaTransitions: schedule.actions
        .filter(({ type }) => [
          "schema-compatibility",
          "schema-upgrade",
          "open-view",
        ].includes(type))
        .map(({ type, author, view, fromView }) => ({
          operation: type,
          author,
          view,
          ...(fromView === undefined ? {} : { fromView }),
          ...(type === "schema-compatibility" ? {
            compatibility: {
              canView: false,
              canUpgrade: true,
              isEquivalent: false,
            },
          } : {}),
        })),
      transactions: schedule.actions
        .filter(({ type }) => type === "transaction")
        .map((action) => ({
          author: action.author,
          constraints: action.constraints,
          requestedResult: action.result,
          outcome: action.result === "abort" ? "aborted" : "committed",
          editsApplied: action.edits.length,
          nestedScopes: action.edits.filter(({ op }) => op === "transaction").length,
          commitRevision: action.result === "abort"
            ? null
            : `${prefix}-${action.author}-transaction`,
          outboundCount: action.result === "abort" ? 0 : 1,
          events: [],
        })),
      undoRedo: schedule.actions
        .filter(({ type }) => ["retain", "revert", "dispose"].includes(type))
        .map((action) => ({
          type: action.type === "revert" ? action.lifecycle : action.type,
          lifecycle: action.lifecycle,
          author: action.author,
          name: action.name,
          ...(action.dispose === undefined ? {} : { dispose: action.dispose }),
          result: action.type === "retain"
            ? {
                name: action.name,
                kind: action.lifecycle === "undo" ? "Undo" : "Default",
                factoryAvailable: true,
                status: "Valid",
              }
            : action.type === "revert"
              ? {
                  name: action.name,
                  authoredKind: action.lifecycle === "redo" ? "Redo" : "Undo",
                  status: action.dispose ? "Disposed" : "Valid",
                  settlement: "Pending",
                  authoredCount: 1,
                  outboundCount: 1,
                }
              : {
                  name: action.name,
                  status: "Disposed",
                },
        })),
    };
    const lifecycleAuthor = item.actions.find(
      ({ type, lifecycle }) => type === "retain" && lifecycle === "edit",
    )?.author;
    const lifecycleObservation = item.checkpoints.at(-1).observations.find(
      ({ implementation }) => implementation === lifecycleAuthor,
    );
    lifecycleObservation.commits = [
      {
        type: "commit",
        kind: "Undo",
        local: true,
        factoryAvailable: true,
        handleAcquired: true,
      },
      { type: "settlement", kind: "Undo", outcome: "FullyApplied" },
      {
        type: "commit",
        kind: "Redo",
        local: true,
        factoryAvailable: true,
        handleAcquired: true,
      },
      { type: "settlement", kind: "Redo", outcome: "FullyApplied" },
    ];
    item.evidence.rawSequencedOperationCount = 30;
    const releaseActions = item.actions.filter(({ type }) => type === "release");
    const outboundActions = releaseActions.filter(({ direction }) => direction === "outbound");
    const acceptedSequenceNumbers = outboundActions.map((_action, releaseIndex) =>
      21 + releaseIndex);
    for (const [releaseIndex, action] of outboundActions.entries()) {
      const submission = item.evidence.submissions.find(
        ({ author }) => author === action.author,
      );
      submission.outerSequenceNumber = acceptedSequenceNumbers[releaseIndex];
    }
    item.evidence.releases = releaseActions.map((action) => {
      if (action.direction === "outbound") {
        const releaseIndex = outboundActions.indexOf(action);
        return {
          author: action.author,
          direction: "outbound",
          order: "fifo",
          afterSequence: 20 + releaseIndex,
          pendingTreeCount: 1,
          acceptedCommitCount: 1,
          acceptedSequenceNumbers: [acceptedSequenceNumbers[releaseIndex]],
        };
      }
      return action.author === "upstream"
        ? {
          author: "upstream",
          direction: "inbound",
          order: "fifo",
          receivedThrough: acceptedSequenceNumbers.at(-1),
          queuedCount: acceptedSequenceNumbers.length,
        }
        : {
          author: action.author,
          direction: "inbound",
          order: action.order,
          heldSequenceNumbers: acceptedSequenceNumbers,
          deliveredSequenceNumbers: action.order === "reverse"
            ? acceptedSequenceNumbers.toReversed()
            : acceptedSequenceNumbers,
        };
    });
    item.artifacts = [artifact(
      "seeded",
      String(index),
      item.documentId,
      { measured: {
        index: item.index,
        seed: item.seed,
        subSeed: item.subSeed,
        template: item.template,
        roles: item.roles,
        actions: item.actions,
        documentId: item.documentId,
        instanceIds: item.instanceIds,
        authorCoverage: item.authorCoverage,
        checkpoints: item.checkpoints,
        identityMapping: item.identityMapping,
        summaries: item.summaries,
        reloads: item.reloads,
        schemaTransitions: item.schemaTransitions,
        transactions: item.transactions,
        undoRedo: item.undoRedo,
        evidence: item.evidence,
      }, ...rawGates() },
    )];
    return item;
  });
  for (const item of [...deterministic, ...seeded]) {
    item.profileDigest = loaded.profileDigest;
  }
  const reload = Object.fromEntries(implementations.map((writer, writerIndex) => [
    writer,
    Object.fromEntries(implementations.map((reader, readerIndex) => {
      const item = {
        runId: "current",
        profileDigest: loaded.profileDigest,
        writer,
        reader,
        writerVersion: `${writer}-version`,
        loadedVersion: `${writer}-version`,
        readerInstanceId: `reload-${writer}-${reader}`,
        snapshotSequenceNumber: 30 + writerIndex,
        dataEditSequenceNumber: 40 + readerIndex,
        publicationSequenceNumber: 50 + writerIndex,
        replayWatermark: 60 + readerIndex,
        replayStartSequenceNumber: 30 + writerIndex,
        replayEvidence: reader === "upstream"
          ? "upstream-delta-storage"
          : "native-handshake",
        selectedSummaryRequests: [`${writer}-version`],
        loaded: true,
        continuedEditing: true,
        scenarioId: "summary-tail",
        peerObservedEdit: true,
        pendingTreeCount: 0,
        inflightSubmissionCount: 0,
        wholeTree: { schemaId: "org.watershed.shared-tree.m1.Root" },
        documentId: `reload-${writer}`,
        writerVersionBeforeLoad: `${writer}-version`,
        writerVersionAfterLoad: `${writer}-version`,
        tailSequenceNumber: 55 + writerIndex,
        retained: {
          visible: { x: 3, y: 4 },
          detached: { x: 42, y: 7 },
          removed: [[0, 1, {
            type: "org.watershed.shared-tree.m1.Point",
            fields: {
              x: [{ type: "com.fluidframework.leaf.number", value: 42 }],
              y: [{ type: "com.fluidframework.leaf.number", value: 7 }],
            },
          }]],
          writerIdentity: {
            clientIds: [`${writer}-client`],
            originatorIds: [`${writer}-origin`],
            resubmissions: writer === "upstream" ? [] : [
              {
                referenceSequenceNumber: 30,
                revision: 1,
                originatorId: `${writer}-origin`,
                refresher: [1, 2],
              },
              {
                referenceSequenceNumber: 30,
                revision: 2,
                originatorId: `${writer}-origin`,
                refresher: [42, 2],
              },
            ],
          },
          upstreamSelectedVersion: `${writer}-version`,
          summaryConsumed: true,
        },
        continuationIdentity: {
          clientId: `${reader}-client`,
          referenceSequenceNumber: 60,
          revisions: [{ revision: 1, originatorId: `${reader}-origin` }],
        },
        artifacts: [],
      };
      item.artifacts = [artifact(
          "reload",
          `${writer}->${reader}`,
          `reload-${writer}`,
          {
            measured: reloadMeasuredPayload(item),
            ...(reader === "upstream" ? {} : {
              raw: {
                load: {
                  handshakes: [{
                    checkpointSequenceNumber: item.snapshotSequenceNumber,
                    summarySequenceNumber: item.snapshotSequenceNumber,
                    initialMessageSequenceNumbers: [
                      1,
                      item.snapshotSequenceNumber + 1,
                    ],
                  }],
                  repairRequests: [],
                },
              },
            }),
          },
        )];
      return [reader, item];
    })),
  ]));
  const mapReload = Object.fromEntries(implementations.map((writer, writerIndex) => [
    writer,
    Object.fromEntries(implementations.map((reader, readerIndex) => {
      const item = {
        runId: "current",
        profileDigest: loaded.profileDigest,
        profile: "map",
        writer,
        reader,
        writerVersion: `${writer}-map-version`,
        loadedVersion: `${writer}-map-version`,
        readerInstanceId: `map-reload-${writer}-${reader}`,
        snapshotSequenceNumber: 70 + writerIndex,
        dataEditSequenceNumber: 80 + readerIndex,
        publicationSequenceNumber: 90 + writerIndex,
        replayWatermark: 100 + readerIndex,
        replayStartSequenceNumber: 70 + writerIndex,
        replayEvidence: reader === "upstream"
          ? "upstream-delta-storage"
          : "native-handshake",
        selectedSummaryRequests: [`${writer}-map-version`],
        scenarioId: "map-summary-tail-retained",
        loaded: true,
        tailObserved: true,
        continuedEditing: true,
        peerObservedEdit: true,
        deletedEntryAbsent: true,
        pendingTreeCount: 0,
        inflightSubmissionCount: 0,
        wholeTree: {
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
        },
        retained: {
          removed: [[0, 1, {
            type: "org.watershed.shared-tree.m2.Point",
            fields: {},
          }]],
          deletedKey: "deleted",
          summaryConsumed: true,
        },
        documentId: `map-reload-${writer}`,
        writerVersionBeforeLoad: `${writer}-map-version`,
        writerVersionAfterLoad: `${writer}-map-version`,
        tailSequenceNumber: 95 + writerIndex,
        continuationIdentity: {
          clientId: `${reader}-map-client`,
          referenceSequenceNumber: 100,
          revisions: [{ revision: 1, originatorId: `${reader}-map-origin` }],
        },
        artifacts: [],
      };
      item.artifacts = [artifact(
        "map-reload",
        `${writer}->${reader}`,
        item.documentId,
        {
          measured: reloadMeasuredPayload(item),
          ...(reader === "upstream" ? {} : {
            raw: {
              load: {
                handshakes: [{
                  checkpointSequenceNumber: item.snapshotSequenceNumber,
                  summarySequenceNumber: item.snapshotSequenceNumber,
                  initialMessageSequenceNumbers: [
                    1,
                    item.snapshotSequenceNumber + 1,
                  ],
                }],
                repairRequests: [],
              },
            },
          }),
        },
      )];
      return [reader, item];
    })),
  ]));
  const schemaCompatibility = implementations.map((target) => {
    const item = {
      runId: "current",
      profileDigest: loaded.profileDigest,
      target,
      protocolVersion: reference.version,
      skipped: false,
      observations: [{
        storedView: "v1",
        requestedView: "optional",
        documentId: `schema-compatibility-${target}`,
        instanceId: `schema-compatibility-${target}-instance`,
        compatibility: {
          canView: false,
          canUpgrade: true,
          isEquivalent: false,
        },
      }],
    };
    item.artifacts = [artifact(
      "schema-compatibility",
      target,
      item.observations[0].documentId,
      { result: structuredClone(item) },
    )];
    return item;
  });
  const schemaRaces = requiredSchemaRaceCells().map((cell, index) => {
    const documentId = `schema-race-${index}`;
    const instanceIds = Object.fromEntries(implementations.map((target) =>
      [target, `${documentId}-${target}`]));
    const losingAuthor = cell.order === "upgrade-first"
      ? cell.competitor
      : cell.upgrader;
    const pendingHistory = {
      pending: [{
        revision: 2,
        originatorId: `${cell.id}-origin-2`,
        changeset: {
          changeCount: cell.family === "schema-schema" ? 0 : 1,
          raw: "Changeset([])",
        },
      }],
    };
    const observation = cell.family === "upgrade-then-edit"
      ? {
        referenceSequenceNumbers: [70 + index, 71 + index],
        dependentEditRetained: true,
      }
      : {
        sequenceNumbers: [70 + index * 2, 71 + index * 2],
        referenceSequenceNumbers: [60 + index, 60 + index],
        submissions: [
          {
            outerSequenceNumber: 70 + index * 2,
            clientId: `${cell.id}-first`,
            referenceSequenceNumber: 60 + index,
            commits: [{
              revision: 1,
              originatorId: `${cell.id}-origin-1`,
              changeset: [{ schema: {} }],
            }],
          },
          {
            outerSequenceNumber: 71 + index * 2,
            clientId: `${cell.id}-second`,
            referenceSequenceNumber: 60 + index,
            commits: [{
              revision: 2,
              originatorId: `${cell.id}-origin-2`,
              changeset: [{ data: {} }],
            }],
          },
        ],
        losingAuthor,
        losingSubmission: {
          outerSequenceNumber: 71 + index * 2,
          commits: [{
            revision: 2,
            originatorId: `${cell.id}-origin-2`,
            changeset: [{ schema: { old: {}, new: {} } }],
          }],
        },
        ...(cell.family === "schema-schema"
          ? {
            originalPending: {
              revision: 2,
              originatorId: `${cell.id}-origin-2`,
              changeset: {
                changeCount: 1,
                raw: [{ schema: { old: {}, new: {} } }],
              },
            },
            reconciledPending: pendingHistory.pending[0],
          }
          : {}),
        rollback: {
          label: "loser-before-ack",
          stage: "intermediate",
          observations: implementations.map((implementation) => ({
            implementation,
            instanceId: instanceIds[implementation],
            sequenceNumber: 70 + index * 2,
            pendingTreeCount: implementation === losingAuthor ? 1 : 0,
            inflightSubmissionCount: implementation === losingAuthor ? 1 : 0,
            wholeTree: { schemaId: "org.watershed.shared-tree.m4.Root" },
            events: [],
            history: implementation === losingAuthor ? pendingHistory : { pending: [] },
          })),
        },
        notifications: Object.fromEntries(implementations.map((implementation) => [
          implementation,
          {
            schema: [{ kind: "schema", local: implementation === cell.upgrader }],
            data: cell.family === "schema-data"
              ? [{ kind: "data", local: implementation === cell.competitor }]
              : [],
          },
        ])),
        intermediateRollback: cell.family === "schema-schema",
        oldViewRejected: true,
        documentHealthy: true,
      };
    const item = {
      ...cell,
      runId: "current",
      profileDigest: loaded.profileDigest,
      documentId,
      instanceIds,
      skipped: false,
      observations: [observation],
    };
    item.artifacts = [artifact("schema-races", cell.id, documentId, {
      result: structuredClone(item),
    })];
    return item;
  });
  const schemaReconnect = implementations.map((target) => {
    const item = {
      runId: "current",
      profileDigest: loaded.profileDigest,
      target,
      skipped: false,
      observations: [
      {
        caseId: "upgrade-unacknowledged",
        documentId: `schema-reconnect-${target}-unacknowledged`,
        instanceId: `schema-reconnect-${target}-unacknowledged-instance`,
        acceptedBeforeDrop: false,
        acceptedSequenceNumber: null,
        pendingTreeCount: 2,
        originalRevisions: ["upgrade", "data"],
        originalOperations: [
          {
            revision: "upgrade",
            originatorId: target,
            payload: [{ schema: { old: {}, new: { upgraded: true } } }],
          },
          {
            revision: "data",
            originatorId: target,
            payload: [{ data: { path: ["score"], value: 81 } }],
          },
        ],
        acceptedCommits: [
          {
            revision: 1,
            originatorId: target,
            kinds: ["schema"],
            changeset: [{ schema: { old: {}, new: { upgraded: true } } }],
          },
          {
            revision: 2,
            originatorId: target,
            kinds: ["data"],
            changeset: [{ data: { path: ["score"], value: 81 } }],
          },
        ],
        acceptedMappings: [
          { originalRevision: "upgrade", acceptedRevision: 1 },
          { originalRevision: "data", acceptedRevision: 2 },
        ],
        orderedReplay: true,
        exactlyOnce: true,
        allClientsObservedDependentData: true,
        pending: { history: { pending: [{}, {}] } },
      },
      {
        caseId: "upgrade-accepted-before-drop",
        documentId: `schema-reconnect-${target}-accepted`,
        instanceId: `schema-reconnect-${target}-accepted-instance`,
        acceptedBeforeDrop: true,
        acceptedSequenceNumber: 80,
        pendingTreeCount: 2,
        originalRevisions: ["upgrade", "data"],
        originalOperations: [
          {
            revision: "upgrade",
            originatorId: target,
            payload: [{ schema: { old: {}, new: { upgraded: true } } }],
          },
          {
            revision: "data",
            originatorId: target,
            payload: [{ data: { path: ["score"], value: 82 } }],
          },
        ],
        acceptedCommits: [
          {
            revision: 1,
            originatorId: target,
            kinds: ["schema"],
            changeset: [{ schema: { old: {}, new: { upgraded: true } } }],
          },
          {
            revision: 2,
            originatorId: target,
            kinds: ["data"],
            changeset: [{ data: { path: ["score"], value: 82 } }],
          },
        ],
        acceptedMappings: [
          { originalRevision: "upgrade", acceptedRevision: 1 },
          { originalRevision: "data", acceptedRevision: 2 },
        ],
        orderedReplay: true,
        exactlyOnce: true,
        allClientsObservedDependentData: true,
        pending: { history: { pending: [{}, {}] } },
      },
      ],
      artifacts: [],
    };
    item.artifacts = item.observations.map((observation) => artifact(
      "schema-reconnect",
      `${target}:${observation.caseId}`,
      observation.documentId,
      { result: structuredClone(observation) },
    ));
    return item;
  });
  const schemaReloadMatrix = Object.fromEntries(implementations.map((writer) => [
    writer,
    Object.fromEntries(implementations.map((reader) => {
      const item = {
        runId: "current",
        profileDigest: loaded.profileDigest,
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
          pendingSummaryVersion: `${writer}-baseline-version`,
          pendingSummaryPublication: {
            version: `${writer}-baseline-version`,
            snapshotSequenceNumber: 90,
            publicationSequenceNumber: 91,
          },
          pendingPublicationVerification: {
            checkpoint: {
              wholeTree: { value: { title: `retained-${writer}` } },
              history: { storedSchema: {} },
            },
            load: {
              selectedSummaryRequests: [`${writer}-baseline-version`],
            },
          },
          captureSequencedCheckpoint: {
            wholeTree: { value: { title: `retained-${writer}` } },
            history: { storedSchema: {} },
          },
          pendingSummaryReferenceSequenceNumber: 90,
          pendingSummaryCapture: {
            sequenceNumber: 90,
            schema: { content: "{}" },
            forest: [{ content: "{}" }],
          },
          pendingSummaryInitialCapture: {
            sequenceNumber: 90,
            schema: {
              content: writer === "upstream"
                ? "{\"upgraded\":true}"
                : "{}",
            },
            forest: [{ content: "{}" }],
          },
          pendingSummaryCaptureSourceBehavior: writer === "upstream"
            ? "upstream-optimistic-encoder-retained-future-state"
            : "stable-reference",
          captureEncoderReference: {
            sequenceNumber: 90,
            schema: { content: "{}" },
            forest: [{ content: "{}" }],
          },
          retainedEncoderReference: {
            sequenceNumber: 90,
            schema: { content: "{}" },
            forest: [{ content: "{}" }],
          },
          sequencedEncoderReference: {
            sequenceNumber: 91,
            schema: { content: "{\"upgraded\":true}" },
            forest: [{ content: "{\"schema\":\"upgraded\"}" }],
          },
          pendingSummaryBinding: {
            schema: "sequenced-at-capture",
            forest: "sequenced-at-capture",
            captureSequenceNumber: 90,
            upgradeSequenceNumber: 91,
          },
          upgradedSummaryVersion: `${writer}-pending-version`,
          schemaUpgradeSequenceNumber: 91,
          snapshotSequenceNumber: 92,
          acceptedUpgrade: {
            outerSequenceNumber: 91,
            commits: [{
              revision: "upgrade",
              originatorId: `${writer}-origin`,
              changeset: [{ schema: { old: {}, new: { upgraded: true } } }],
            }],
          },
          sequencedWriterCheckpoint: {
            sequenceNumber: 91,
            pendingTreeCount: 0,
          },
          retainedPeerAuthor: writer === "upstream" ? "javascript" : "upstream",
          retainedPeerCheckpoint: {
            history: {
              pending: [{
                revision: "retained-peer",
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
            outerSequenceNumber: 90,
            commits: [{
              revision: "retained-peer",
              originatorId: `${writer}-peer-origin`,
              changeset: [{
                data: { path: ["title"], value: `retained-${writer}` },
              }],
            }],
          },
          pendingWriterInstanceId: `${writer}-pending-writer`,
          pendingWriterCheckpoint: {
            history: {
              pending: [{
                revision: "upgrade",
                originatorId: `${writer}-origin`,
                changeset: {
                  changeCount: 1,
                  raw: { changes: [{ type: "schema" }] },
                },
              }],
            },
          },
          pendingStoredState: {
            version: `${writer}-baseline-version`,
            rootTreeId: `${writer}-root-tree`,
            treeIds: [`${writer}-root-tree`, `${writer}-schema-tree`],
            blobIds: [
              `${writer}-schema-blob`,
              `${writer}-forest-blob`,
            ],
            schema: {
              path: ".app/.channels/A/.channels/_C/indexes/Schema/SchemaString",
              id: `${writer}-schema-blob`,
              byteLength: 2,
              hash: "a".repeat(64),
              content: "{}",
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
            version: `${writer}-pending-version`,
            rootTreeId: `${writer}-tree`,
            treeIds: [`${writer}-tree`],
            blobIds: [
              `${writer}-upgraded-schema-blob`,
              `${writer}-upgraded-forest-blob`,
            ],
              schema: {
                id: `${writer}-upgraded-schema-blob`,
                content: "{\"upgraded\":true}",
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
                  revision: "retained-peer",
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
                  revision: "upgrade",
                  changeset: {
                    changeCount: 1,
                    raw: {
                      changes: [{
                        type: "schema",
                        innerChange: {
                          schema: { old: {}, new: { upgraded: true } },
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
                  revision: "retained-peer",
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
                  revision: "upgrade",
                  changeset: {
                    changeCount: 1,
                    raw: {
                      changes: [{
                        type: "schema",
                        innerChange: {
                          schema: { old: {}, new: { upgraded: true } },
                        },
                      }],
                    },
                  },
                },
              ],
            },
          },
          documentId: `schema-reload-${writer}`,
          loadedVersion: `${writer}-pending-version`,
          selectedSummaryRequests: [`${writer}-pending-version`],
          selectedSummaryTreeId: `${writer}-tree`,
          selectedTreeRequests: [`${writer}-tree`],
          selectedBlobRequests: reader === "upstream"
            ? [{
              id: `${writer}-upgraded-schema-blob`,
              byteLength: 100,
              hash: "b".repeat(64),
            }]
            : [`${writer}-upgraded-schema-blob`],
          replayStartSequenceNumber: 90,
          replayWatermark: 92,
          replayEvidence: reader === "upstream"
            ? "upstream-delta-storage"
            : "native-handshake",
          readerInstanceId: `${writer}-${reader}-schema-reader`,
        }],
        artifacts: [],
      };
      item.artifacts = [artifact(
        "schema-reload",
        `${writer}-${reader}`,
        `schema-reload-${writer}`,
        {
          result: Object.fromEntries(Object.entries(item)
            .filter(([name]) => name !== "artifacts")),
        },
      )];
      return [reader, item];
    })),
  ]));
  const schemaTailReloadMatrix = structuredClone(schemaReloadMatrix);
  for (const [writer, row] of Object.entries(schemaTailReloadMatrix)) {
    for (const [reader, item] of Object.entries(row)) {
      const observation = item.observations[0];
      observation.loadedVersion = observation.pendingSummaryVersion;
      observation.summaryKind = "earlier-summary-upgrade-tail";
      observation.snapshotSequenceNumber = 90;
      observation.publicationSequenceNumber = 91;
      observation.dataEditSequenceNumber = 90;
      observation.replayStartSequenceNumber = 90;
      observation.selectedSummaryRequests = [observation.loadedVersion];
      observation.selectedSummaryTreeId = observation.pendingStoredState.rootTreeId;
      observation.selectedTreeRequests = [observation.pendingStoredState.rootTreeId];
      observation.selectedBlobRequests = [observation.pendingStoredState.schema.id];
      item.artifacts = [artifact(
        "schema-tail-reload",
        `${writer}-${reader}`,
        observation.documentId,
        {
          result: Object.fromEntries(Object.entries(item)
            .filter(([name]) => name !== "artifacts")),
        },
      )];
    }
  }
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
  const array = (schemaId, elements) => ({ kind: "array", schemaId, elements });
  const arrayTree = (writer, continuation) => ({
    present: true,
    value: {
      kind: "object",
      schemaId: "org.watershed.shared-tree.m3.Root",
      fields: [
        ["byKey", {
          kind: "map",
          schemaId: "org.watershed.shared-tree.m3.ArrayMap",
          entries: [
            ["", array("org.watershed.shared-tree.m3.Items", [])],
            ["0", array("org.watershed.shared-tree.m3.Items", [
              arrayPoint("numeric", 0),
            ])],
          ],
        }],
        ["left", array("org.watershed.shared-tree.m3.Items", [
          ...(continuation ? [arrayPoint(continuation, 42)] : []),
          arrayPoint("duplicate", 1),
          arrayPoint("duplicate", 1),
          array("org.watershed.shared-tree.m3.Items", [arrayPoint("nested", 2)]),
        ])],
        ["narrow", array("org.watershed.shared-tree.m3.Points", [])],
        ["right", array("org.watershed.shared-tree.m3.Items", [
          {
            kind: "map",
            schemaId: "org.watershed.shared-tree.m3.ArrayMap",
            entries: [["inside", arrayPoint("map-child", 3)]],
          },
          ...(continuation ? [] : [arrayPoint("moved", 4)]),
          arrayPoint(`after-summary-${writer}`, 7),
        ])],
      ],
    },
  });
  const arrayReload = Object.fromEntries(implementations.map((writer, writerIndex) => [
    writer,
    Object.fromEntries(implementations.map((reader, readerIndex) => {
      const continuation = `${writer}-${reader}-continuation`;
      const item = {
        runId: "current",
        profileDigest: loaded.profileDigest,
        profile: "array",
        writer,
        reader,
        writerVersion: `${writer}-array-version`,
        loadedVersion: `${writer}-array-version`,
        readerInstanceId: `array-reload-${writer}-${reader}`,
        snapshotSequenceNumber: 110 + writerIndex,
        dataEditSequenceNumber: 120 + writerIndex,
        publicationSequenceNumber: 130 + writerIndex,
        tailSequenceNumber: 140 + writerIndex,
        replayWatermark: 150 + readerIndex,
        replayStartSequenceNumber: 110 + writerIndex,
        replayEvidence: reader === "upstream"
          ? "upstream-delta-storage"
          : "native-handshake",
        selectedSummaryRequests: [`${writer}-array-version`],
        scenarioId: "array-summary-tail-retained",
        loaded: true,
        tailObserved: true,
        continuedEditing: true,
        peerObservedEdit: true,
        pendingTreeCount: 0,
        inflightSubmissionCount: 0,
        wholeTree: arrayTree(writer),
        continuationTree: arrayTree(writer, continuation),
        peerWholeTree: arrayTree(writer, continuation),
        continuationLabel: continuation,
        retained: {
          removed: [[0, 1, removedArrayPoint()]],
          reader,
          readerInstanceId: `array-reload-${writer}-${reader}`,
          source: reader === "upstream"
            ? "upstream-runtime-and-wire"
            : "native-runtime-snapshot",
          loadedVersion: `${writer}-array-version`,
          snapshotSequenceNumber: 110 + writerIndex,
          sequenceNumber: 110 + writerIndex,
          selectedVersion: `${writer}-array-version`,
          history: [{
            revision: 1,
            originatorId: `${reader}-array-origin`,
            changes: [{
              moveOut: { id: 0 },
              moveIn: { id: 0 },
            }],
          }],
          moveIdentity: {
            revision: 1,
            originatorId: `${reader}-array-origin`,
            moveOut: [{ id: 0, revision: 1 }],
            moveIn: [{ id: 0, revision: 1 }],
          },
          childEditObserved: true,
          summaryConsumed: true,
        },
        continuationIdentity: {
          clientId: `${reader}-array-client`,
          referenceSequenceNumber: 150,
          revisions: [{ revision: 1, originatorId: `${reader}-array-origin` }],
        },
        documentId: `array-reload-${writer}`,
        writerVersionBeforeLoad: `${writer}-array-version`,
        writerVersionAfterLoad: `${writer}-array-version`,
        artifacts: [],
      };
      item.artifacts = [artifact(
        "array-reload",
        `${writer}->${reader}`,
        item.documentId,
        {
          measured: reloadMeasuredPayload(item),
          ...(reader === "upstream" ? {} : {
            raw: {
              load: {
                handshakes: [{
                  checkpointSequenceNumber: item.snapshotSequenceNumber,
                  summarySequenceNumber: item.snapshotSequenceNumber,
                  initialMessageSequenceNumbers: [
                    1,
                    item.snapshotSequenceNumber + 1,
                  ],
                }],
                repairRequests: [],
              },
            },
          }),
        },
      )];
      return [reader, item];
    })),
  ]));
  const identifierFields = {
    pairs: identifierPairCells().map((cell) => {
      const documentId = `identifier-${cell.id}`;
      const item = {
        ...cell,
        runId: "current",
        profileDigest: loaded.profileDigest,
        documentId,
        passed: true,
        skipped: false,
        authors: Object.fromEntries(cell.authors.map((author) => [author, {
          defaultId: `${author}-generated`,
          explicitId: "shared-custom-id",
          peerObserved: true,
          constraintsUseNodeIdentity: true,
          movedWithinArray: true,
          movedBetweenArrays: true,
          equalIdReplacementChangedReference: true,
        }])),
        artifacts: [],
      };
      item.artifacts = [artifact("identifier-fields", item.id, documentId, {
        measured: {
          authors: item.authors,
          passed: true,
          skipped: false,
        },
      })];
      return item;
    }),
    failures: failures
      .filter(({ caseId }) => [
        "missing-allocation",
        "wrong-originator",
        "corrupt-numeric-identifier",
        "negative-originatorless-summary",
      ].includes(caseId))
      .map((item) => ({
        caseId: item.caseId,
        target: item.target,
        runId: item.runId,
        profileDigest: item.profileDigest,
        documentId: item.documentId,
        outcome: item.outcome,
        failureObserved: true,
        partialReadinessObserved: false,
        partialMutationObserved: false,
        typedError: item.typedError,
        artifacts: [artifact(
          "identifier-refusal",
          `${item.caseId}:${item.target}`,
          item.documentId,
        )],
      })),
  };
  const identifierReloadMatrix = Object.fromEntries(implementations.map((writer) => [
    writer,
    Object.fromEntries(implementations.map((reader) => {
      const documentId = `${writer}-identifier-document`;
      const item = {
        runId: "current",
        profileDigest: loaded.profileDigest,
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
          implementation: "upstream",
          id: `${writer}-${reader}-generated`,
          observed: true,
        },
        pendingTreeCount: 0,
        inflightSubmissionCount: 0,
        documentId,
        artifacts: [],
      };
      item.artifacts = [artifact(
        "identifier-reload",
        `${writer}->${reader}`,
        documentId,
        {
          measured: {
            writerAuthored: item.writerAuthored,
            postLoadAuthored: item.postLoadAuthored,
            peerObservation: item.peerObservation,
          },
        },
      )];
      return [reader, item];
    })),
  ]));
  const transactionCallbacks = {
    pairs: transactionPairCells().map((cell) => {
      const documentId = `transaction-${cell.id}`;
      const item = {
        ...cell,
        runId: "current",
        profileDigest: loaded.profileDigest,
        documentId,
        passed: true,
        skipped: false,
        authors: Object.fromEntries(cell.authors.map((author) => [author, {
          commit: {
            outcome: "committed",
            callbackObservedEdits: true,
            nestedScopes: 1,
            nestedOutcome: "committed",
            editsApplied: 2,
            commitRevision: `${author}-revision`,
            outboundCount: 1,
            acceptedCommitCount: 1,
            localEventCount: 1,
            peerObservedAtomically: true,
          },
          abort: {
            outcome: "aborted",
            callbackObservedEdits: true,
            editsApplied: 1,
            commitRevision: null,
            outboundCount: 0,
            acceptedCommitCount: 0,
            localEventCount: 0,
            treeUnchanged: true,
            peerObserved: false,
          },
          movedWithinArray: true,
          movedBetweenArrays: true,
        }])),
        artifacts: [],
      };
      item.artifacts = [artifact("transaction-callbacks", item.id, documentId, {
        measured: { authors: item.authors, passed: true, skipped: false },
      })];
      return item;
    }),
  };
  const transactionConstraints = transactionConstraintCells().map((cell) => {
    const documentId = `transaction-constraint-${cell.id}`;
    const applied = cell.order === "transaction-first";
    const item = {
      ...cell,
      runId: "current",
      profileDigest: loaded.profileDigest,
      documentId,
      passed: true,
      skipped: false,
      transactionApplied: applied,
      constraintViolated: !applied,
      converged: true,
      sequenced: (applied
        ? [cell.author, cell.remover]
        : [cell.remover, cell.author]).map((author, index) => ({
        author,
        sequenceNumber: 20 + index,
      })),
      artifacts: [],
    };
    item.artifacts = [artifact("transaction-constraint", item.id, documentId, {
      measured: {
        transactionApplied: item.transactionApplied,
        constraintViolated: item.constraintViolated,
        converged: item.converged,
        sequenced: item.sequenced,
      },
    })];
    return item;
  });
  const transactionReconnect = implementations.slice(1).flatMap((target) =>
    transactionCaseIds.map((caseId, index) => {
      const subject = `${target}:${caseId}`;
      const documentId = `transaction-reconnect-${subject}`;
      return {
        target,
        caseId,
        runId: "current",
        profileDigest: loaded.profileDigest,
        profile: "fluid-3.1.0-fixed-object",
        documentId,
        passed: true,
        skipped: false,
        evidence: {
          sequenceNumber: 24,
          clientId: `${target}-${caseId}`,
          pendingTreeCount: 0,
          transaction: {
            committed: {
              outcome: "committed",
              outboundCount: 1,
              localEventCount: 1,
              nestedScopes: 1,
              editsApplied: 2,
              commitRevision: `${target}-transaction-revision`,
            },
            aborted: {
              outcome: "aborted",
              outboundCount: 0,
              localEventCount: 0,
              commitRevision: null,
            },
            pendingTreeCountWhileHeld: 1,
            resubmittedCommitCount: 1,
            peerObserved: true,
            abortPeerObserved: false,
          },
          checkpoints: ["held", "reconnected"].map((label) => ({
            label,
            sequenceNumber: 24,
            clientId: `${target}-${caseId}`,
            pendingTreeCount: 0,
            values: {},
            events: [],
          })),
          submissions: [{
            sequenceNumber: 24,
            batchId: `${target}-transaction-${index}`,
            revision: index,
            originatorId: target,
          }],
          artifacts: [artifact("transaction-reconnect", subject, documentId)],
        },
      };
    }));
  const transactionReloadMatrix = Object.fromEntries(implementations.map((writer) => [
    writer,
    Object.fromEntries(implementations.map((reader) => {
      const documentId = `${writer}-transaction-document`;
      const item = {
        runId: "current",
        profileDigest: loaded.profileDigest,
        profile: "array",
        writer,
        reader,
        writerVersion: `${writer}-transaction-version`,
        loadedVersion: `${writer}-transaction-version`,
        readerInstanceId: `${writer}-${reader}-transaction-reader`,
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
        documentId,
        artifacts: [],
      };
      item.artifacts = [artifact(
        "transaction-reload",
        `${writer}->${reader}`,
        documentId,
        {
          measured: {
            writerAuthored: item.writerAuthored,
            postLoadAuthored: item.postLoadAuthored,
            peerObservation: item.peerObservation,
          },
        },
      )];
      return [reader, item];
    })),
  ]));
  const undoCommitEvents = (local) => [
    ...["Default", "Undo", "Redo"].map((kind) => ({
      type: "commit",
      kind,
      local,
      factoryAvailable: local,
      handleAcquired: local,
    })),
    ...["Default", "Undo", "Redo"].map((kind) => ({
      type: "settlement",
      kind,
      outcome: "FullyApplied",
    })),
  ];
  const undoRedoConcurrent = [
    ["javascript", "upstream"],
    ["erlang", "upstream"],
    ["javascript", "erlang"],
  ].flatMap((authors) => ["object", "map", "array", "move", "transaction"]
    .flatMap((fieldKind) => ["a-first", "b-first"].map((order) => {
      const id = `undo-redo:${authors.join("<->")}:${fieldKind}:${order}`;
      const expectedSnapshots = {
        authored: { phase: "authored", edit: true, peer: false },
        concurrent: { phase: "concurrent", edit: true, peer: true },
        undone: { phase: "undone", edit: false, peer: true },
        redone: { phase: "redone", edit: true, peer: true },
      };
      const item = {
        id,
        authors,
        fieldKind,
        order,
        runId: "current",
        profileDigest: loaded.profileDigest,
        documentId: `document-${id}`,
        snapshots: structuredClone(expectedSnapshots),
        expectedSnapshots,
        localKinds: ["Default", "Undo", "Redo"],
        factoryAvailability: [true, true, true],
        handleStatuses: ["Valid", "Disposed", "Disposed"],
        settlements: ["FullyApplied", "FullyApplied", "FullyApplied"],
        authoredCounts: [1, 1, 1],
        outboundCounts: [1, 1, 1],
        remoteFactoryAvailable: false,
        finalTree: structuredClone(expectedSnapshots.redone),
        passed: true,
        failed: false,
        skipped: false,
        error: null,
        artifacts: [],
      };
      item.artifacts = [artifact("undo-redo", id, item.documentId, {
        measured: reloadMeasuredPayload(item),
        raw: {
          checkpoints: structuredClone(item.snapshots),
          eventTrace: {
            [authors[0]]: undoCommitEvents(true),
            [authors[1]]: [
              {
                type: "commit",
                kind: "Default",
                local: true,
                factoryAvailable: true,
                handleAcquired: true,
              },
              ...undoCommitEvents(false).filter(({ type }) => type === "commit"),
            ],
            [implementations.find((value) => !authors.includes(value))]: [],
          },
          handleNames: ["edit", "undo"],
        },
      })];
      return item;
    })));
  const undoRedoKinds = {
    implementations: implementations.map((implementation) => {
      const source = undoRedoConcurrent.find(
        ({ authors }) => authors[0] === implementation,
      ) ?? undoRedoConcurrent[0];
      const item = {
        id: implementation,
        implementation,
        sourceId: source.id,
        runId: "current",
        profileDigest: loaded.profileDigest,
        documentId: `undo-kinds-${implementation}`,
        localKinds: ["Default", "Undo", "Redo"],
        factoryAvailability: [true, true, true],
        handleStatuses: ["Valid", "Disposed"],
        settlements: ["FullyApplied", "FullyApplied", "FullyApplied"],
        authoredCounts: [1, 1, 1],
        outboundCounts: [1, 1, 1],
        finalTree: { title: `${implementation}-redo` },
        passed: true,
        failed: false,
        skipped: false,
        error: null,
        artifacts: [],
      };
      item.artifacts = [artifact(
        "undo-redo-kind",
        implementation,
        item.documentId,
        {
          measured: reloadMeasuredPayload(item),
          raw: { sourceId: source.id, sourceArtifacts: source.artifacts },
        },
      )];
      return item;
    }),
  };
  const undoRedoReconnect = ["javascript", "erlang"].map((implementation) => {
    const item = {
      id: `undo-redo-reconnect:${implementation}`,
      implementation,
      runId: "current",
      profileDigest: loaded.profileDigest,
      documentId: `undo-reconnect-${implementation}`,
      liveHandleBeforeDisconnect: "Valid",
      liveHandleAfterReconnect: "Valid",
      undoKind: "Undo",
      settlement: "FullyApplied",
      authoredCount: 1,
      outboundCount: 1,
      expectedTree: { phase: "baseline", peer: true },
      finalTree: { phase: "baseline", peer: true },
      passed: true,
      failed: false,
      skipped: false,
      error: null,
      artifacts: [],
    };
    item.artifacts = [artifact(
      "undo-redo-reconnect",
      item.id,
      item.documentId,
      {
        measured: reloadMeasuredPayload(item),
        raw: {
          eventTrace: undoCommitEvents(true),
          handleNames: ["edit"],
        },
      },
    )];
    return item;
  });
  const undoRedoReloadMatrix = Object.fromEntries(implementations.map((writer) => [
    writer,
    Object.fromEntries(["undo", "redo"].map((stage, stageIndex) => [
      stage,
      Object.fromEntries(implementations.map((reader, readerIndex) => {
        const item = {
          writer,
          reader,
          stage,
          runId: "current",
          profileDigest: loaded.profileDigest,
          documentId: `undo-reload-${writer}-${stage}`,
          writerVersion: `${writer}-${stage}-version`,
          loadedVersion: `${writer}-${stage}-version`,
          snapshotSequenceNumber: 70 + stageIndex,
          replayStartSequenceNumber: 70 + stageIndex + readerIndex,
          selectedSummaryRequests: [`${writer}-${stage}-version`],
          loadEvidence: {
            loadedVersion: `${writer}-${stage}-version`,
            replayStartSequenceNumber: 70 + stageIndex + readerIndex,
            selectedSummaryRequests: [`${writer}-${stage}-version`],
          },
          loaded: true,
          historicalHandleAvailable: false,
          historicalRetainError: "No unretained local commit is available",
          historicalLoadCommits: [],
          newLocalKind: "Default",
          newFactoryAvailable: true,
          newHandleStatus: "Valid",
          undoKind: "Undo",
          settlement: "FullyApplied",
          authoredCount: 1,
          outboundCount: 1,
          finalTree: { writer, reader, stage },
          passed: true,
          failed: false,
          skipped: false,
          error: null,
          artifacts: [],
        };
        item.artifacts = [artifact(
          "undo-redo-reload",
          `${writer}:${stage}->${reader}`,
          item.documentId,
          {
            measured: reloadMeasuredPayload(item),
            raw: {
              load: item.loadEvidence,
              loaded: { commits: [] },
              final: { commits: undoCommitEvents(true) },
              handleNames: ["post-load"],
            },
          },
        )];
        return [reader, item];
      })),
    ])),
  ]));
  const report = {
    formatVersion: 1,
    runId: "current",
    profileDigest: loaded.profileDigest,
    profile: loaded.profile,
    reference,
    service: {
      ...service,
      runId: "current",
      profileDigest: loaded.profileDigest,
      preflightArtifact: artifact(
        "service-preflight",
        "service",
        null,
        { reference, service, realService: true },
      ),
    },
    realService: true,
    mode: "acceptance",
    seed: 42,
    iterations: 300,
    seededAccounting: {
      requested: 300,
      generated: 300,
      executed: 300,
      seed: 42,
      profiles: { object: 60, map: 60, schema: 60, array: 60, identifier: 60 },
    },
    deterministic,
    reconnect,
    failures,
    identifierFields,
    seeded,
    reload,
    mapReload,
    schemaCompatibility,
    schemaRaces,
    schemaReconnect,
    schemaReloadMatrix,
    schemaTailReloadMatrix,
    arrayReload,
    identifierReloadMatrix,
    transactionCallbacks,
    transactionConstraints,
    transactionReconnect,
    transactionReloadMatrix,
    undoRedoKinds,
    undoRedoConcurrent,
    undoRedoReconnect,
    undoRedoReloadMatrix,
    corpus: Object.fromEntries(implementations.slice(1).map((target) => {
      const output = "Running 1 tests\nTests: 1 passed (1)";
      return [target, {
        target,
        runId: "current",
        profileDigest: loaded.profileDigest,
        passed: true,
        skipped: false,
        executedCount: 1,
        artifacts: [artifact("corpus", target, null, {
          command: ["gleam", "test", "--target", target, "--", "shared_tree"],
          exitCode: 0,
          executedCount: 1,
          output,
        })],
      }];
    })),
    skipped: [],
    divergences: [],
  };
  await Promise.all([...artifactFiles].map(([path, value]) =>
    writeFile(join(owned, path), `${JSON.stringify(value)}\n`)));
  const artifacts = await createArtifactEvidence(owned, [...artifactFiles.keys()]);
  const expected = {
    runId: "current",
    profileDigest: loaded.profileDigest,
    profile: loaded.profile,
    seed: 42,
    iterations: 300,
    mode: "acceptance",
    artifactDirectory: owned,
    artifacts,
  };
  return { artifacts, expected, loaded, owned, report };
}

test("an empty result cannot prove interoperability", async () => {
  const { expected, loaded, report } = await validFixture();
  assert.throws(() => validateInteropReport({
    formatVersion: 1,
    runId: "current",
    profileDigest: loaded.profileDigest,
    profile: loaded.profile,
    reference,
    service: {
      ...service,
      runId: "current",
      profileDigest: loaded.profileDigest,
      preflightArtifact: report.service.preflightArtifact,
    },
    realService: true,
    mode: "acceptance",
    seed: 42,
    iterations: 300,
    deterministic: [],
    reconnect: [],
    failures: [],
    seeded: [],
    reload: {},
    mapReload: {},
    arrayReload: {},
    corpus: {},
    skipped: [],
    divergences: [],
  }, expected));
});

test("a complete current-run report satisfies the Task 15 coverage gate", async () => {
  const { expected, report } = await validFixture();
  assert.equal(validateInteropReport(report, expected), report);
});

test("Identifier coverage rejects missing authors, refusals, and reload cells", async () => {
  const cases = [
    {
      mutate(report) {
        report.identifierFields.pairs = report.identifierFields.pairs.filter(
          ({ id }) => !id.includes("erlang"),
        );
      },
      pattern: /pair|erlang|coverage/i,
    },
    {
      mutate(report) {
        report.identifierFields.pairs = report.identifierFields.pairs.filter(
          ({ id }) => !id.includes("upstream"),
        );
      },
      pattern: /pair|upstream|coverage/i,
    },
    {
      mutate(report) {
        report.identifierFields.failures.pop();
      },
      pattern: /refusal|failure|coverage/i,
    },
    {
      mutate(report) {
        delete report.identifierReloadMatrix.upstream.erlang;
      },
      pattern: /reload|reader|cell/i,
    },
  ];
  for (const { mutate, pattern } of cases) {
    const { expected, report } = await validFixture();
    mutate(report);
    assert.throws(() => validateInteropReport(report, expected), pattern);
  }
});

test("transaction coverage rejects missing sections, pairs, orders, and cells", async () => {
  const cases = [
    { mutate(report) { delete report.transactionCallbacks; },
      pattern: /missing transactioncallbacks/i },
    { mutate(report) { delete report.transactionConstraints; },
      pattern: /missing transactionconstraints/i },
    { mutate(report) { delete report.transactionReconnect; },
      pattern: /missing transactionreconnect/i },
    { mutate(report) { delete report.transactionReloadMatrix; },
      pattern: /missing transactionreloadmatrix/i },
    {
      mutate(report) {
        report.transactionCallbacks.pairs = report.transactionCallbacks.pairs
          .filter(({ id }) => !id.includes("erlang"));
      },
      pattern: /three client pairs|lacks/i,
    },
    {
      mutate(report) {
        delete report.transactionCallbacks.pairs[0]
          .authors[report.transactionCallbacks.pairs[0].authors.upstream
            ? "upstream"
            : Object.keys(report.transactionCallbacks.pairs[0].authors)[0]];
      },
      pattern: /lacks a real author/i,
    },
    {
      mutate(report) {
        report.transactionCallbacks.pairs[0]
          .authors[Object.keys(report.transactionCallbacks.pairs[0].authors)[0]]
          .commit.nestedScopes = 0;
      },
      pattern: /nested transaction scope/i,
    },
    {
      mutate(report) {
        report.transactionCallbacks.pairs[0]
          .authors[Object.keys(report.transactionCallbacks.pairs[0].authors)[0]]
          .abort.peerObserved = true;
      },
      pattern: /abort reached a peer/i,
    },
    {
      mutate(report) {
        report.transactionConstraints = report.transactionConstraints
          .filter(({ order }) => order !== "remove-first");
      },
      pattern: /both race orderings/i,
    },
    {
      mutate(report) {
        const cell = report.transactionConstraints
          .find(({ order }) => order === "remove-first");
        cell.transactionApplied = true;
      },
      pattern: /against its race ordering/i,
    },
    {
      mutate(report) {
        report.transactionReconnect[0].evidence.transaction
          .resubmittedCommitCount = 2;
      },
      pattern: /duplicated or lost/i,
    },
    {
      mutate(report) {
        report.transactionReconnect[0].evidence.transaction.aborted
          .outboundCount = 1;
      },
      pattern: /aborted transaction queued an operation/i,
    },
    {
      mutate(report) { delete report.transactionReloadMatrix.upstream.erlang; },
      pattern: /all three readers for upstream/i,
    },
    {
      mutate(report) {
        report.transactionReloadMatrix.javascript.erlang.postLoadAuthored
          .sequencedCommitCount = 2;
      },
      pattern: /not one sequenced commit/i,
    },
    {
      mutate(report) {
        report.transactionReloadMatrix.erlang.upstream.historyVerified = false;
      },
      pattern: /did not verify history/i,
    },
    {
      mutate(report) {
        report.transactionReloadMatrix.erlang.upstream.historyEvidence
          .composedCommitCount = 0;
      },
      pattern: /did not restore the writer's composed commit/i,
    },
    {
      mutate(report) {
        report.transactionReloadMatrix.javascript.javascript.constrainedNode
          .index = 2;
      },
      pattern: /moved to another position/i,
    },
  ];
  for (const { mutate, pattern } of cases) {
    const { expected, report } = await validFixture();
    mutate(report);
    assert.throws(() => validateInteropReport(report, expected), pattern);
  }
});

test("undo and redo coverage rejects missing sections and observations", async () => {
  const cases = [
    ["section", (report) => { delete report.undoRedoKinds; }],
    ["implementation", (report) => {
      report.undoRedoKinds.implementations.pop();
    }],
    ["race ordering", (report) => {
      report.undoRedoConcurrent = report.undoRedoConcurrent.filter(
        ({ order }) => order !== "b-first",
      );
    }],
    ["field-kind row", (report) => {
      report.undoRedoConcurrent = report.undoRedoConcurrent.filter(
        ({ fieldKind }) => fieldKind !== "move",
      );
    }],
    ["reload cell", (report) => {
      delete report.undoRedoReloadMatrix.javascript.redo.erlang;
    }],
    ["settlement observation", (report) => {
      report.undoRedoConcurrent[0].settlements.pop();
    }],
  ];
  for (const [label, mutate] of cases) {
    const { expected, report } = await validFixture();
    mutate(report);
    assert.throws(
      () => validateInteropReport(report, expected),
      /undo|redo|settlement|implementation|race|field|reload/i,
      label,
    );
  }
});

test("undo and redo evidence rejects concrete proof mutations", async () => {
  const cases = [
    ["constant authored count", (report) => {
      report.undoRedoConcurrent[0].authoredCounts[1] = 0;
    }],
    ["inferred reconnect status", (report) => {
      report.undoRedoReconnect[0].liveHandleAfterReconnect = "Invalid";
    }],
    ["wrong converged tree", (report) => {
      report.undoRedoConcurrent[0].snapshots.undone.peer = false;
    }],
    ["lost peer edit in final tree", (report) => {
      report.undoRedoConcurrent[0].finalTree.peer = false;
    }],
    ["missing artifact", (report) => {
      report.undoRedoConcurrent[0].artifacts = [];
    }],
    ["duplicate artifact", (report) => {
      report.undoRedoConcurrent[0].artifacts.push(
        report.undoRedoConcurrent[0].artifacts[0],
      );
    }],
    ["mislabeled artifact", (report) => {
      report.undoRedoConcurrent[0].artifacts =
        report.undoRedoReconnect[0].artifacts;
    }],
    ["wrong run", (report) => {
      report.undoRedoConcurrent[0].runId = "other";
    }],
    ["wrong document", (report) => {
      report.undoRedoConcurrent[0].documentId = "other";
    }],
    ["failed implementation", (report) => {
      report.undoRedoConcurrent[0].failed = true;
    }],
    ["error-shaped implementation", (report) => {
      report.undoRedoConcurrent[0].error = { message: "failed" };
    }],
    ["fake writer version", (report) => {
      report.undoRedoReloadMatrix.javascript.undo.erlang.loadedVersion = "fake";
    }],
    ["fake load evidence", (report) => {
      report.undoRedoReloadMatrix.javascript.undo.erlang
        .loadEvidence.selectedSummaryRequests = ["fake"];
    }],
    ["wrong snapshot sequence", (report) => {
      report.undoRedoReloadMatrix.javascript.undo.erlang
        .replayStartSequenceNumber = 0;
    }],
    ["unrelated historical error", (report) => {
      report.undoRedoReloadMatrix.javascript.undo.erlang
        .historicalRetainError = "Transport timeout";
    }],
    ["historical local factory", (report) => {
      report.undoRedoReloadMatrix.javascript.undo.erlang
        .historicalLoadCommits.push({
          type: "commit",
          local: true,
          factoryAvailable: true,
        });
    }],
    ["missing lifecycle record", (report) => {
      report.seeded[0].undoRedo.pop();
    }],
    ["duplicate lifecycle record", (report) => {
      report.seeded[0].undoRedo.push(structuredClone(report.seeded[0].undoRedo[0]));
    }],
    ["reordered lifecycle record", (report) => {
      report.seeded[0].undoRedo.reverse();
    }],
    ["error-shaped lifecycle result", (report) => {
      report.seeded[0].undoRedo[0].result = { error: "failed" };
    }],
  ];
  for (const [label, mutate] of cases) {
    const { expected, report } = await validFixture();
    mutate(report);
    assert.throws(
      () => validateInteropReport(report, expected),
      undefined,
      label,
    );
  }
});

test("seed 42 integrates legal undo lifetimes across generated schedules", () => {
  const schedules = generateSchedules({ seed: 42, iterations: 300 });
  const intervening = new Set();
  for (const schedule of schedules) {
    const retain = schedule.actions.findIndex(
      ({ type, lifecycle }) => type === "retain" && lifecycle === "edit",
    );
    const undo = schedule.actions.findIndex(
      ({ type, lifecycle }) => type === "revert" && lifecycle === "undo",
    );
    const redo = schedule.actions.findIndex(
      ({ type, lifecycle }) => type === "revert" && lifecycle === "redo",
    );
    const dispose = schedule.actions.findIndex(({ type }) => type === "dispose");
    assert(retain >= 0 && undo > retain && redo > undo && dispose > redo);
    for (const action of schedule.actions.slice(retain + 1, undo)) {
      intervening.add(action.type);
    }
  }
  for (const type of [
    "set",
    "map-set",
    "array-insert",
    "release",
    "checkpoint",
    "transaction",
    "disconnect",
    "reconnect",
    "summarize",
    "reload",
  ]) {
    assert(intervening.has(type), `missing intervening ${type}`);
  }
});

test("seeded failure artifacts retain primary and incremental undo evidence", async () => {
  const directory = await mkdtemp(join(tmpdir(), "watershed-seeded-failure-"));
  const schedule = generateSchedules({ seed: 42, iterations: 1 })[0];
  const error = new Error("primary failure");
  const state = {
    documentId: "document",
    checkpoints: [{
      label: "failure-drain",
      observations: [{
        commits: [
          { type: "commit", kind: "Undo" },
          { type: "settlement", outcome: "FullyApplied" },
        ],
      }],
    }],
    summaries: [],
    schemaTransitions: [],
    transactions: [],
    undoRedo: [{
      type: "retain",
      name: "edit-0",
      result: { kind: "Default", status: "Valid" },
    }],
    currentAction: { index: 3, type: "revert", name: "edit-0" },
  };
  const path = await writeSeededFailure({
    runId: "run",
    profileDigest: "a".repeat(64),
    artifactDirectory: directory,
  }, schedule, state, error);
  const artifact = JSON.parse(await readFile(path, "utf8"));
  assert.equal(artifact.error.message, "primary failure");
  assert.equal(artifact.seed, 42);
  assert.equal(artifact.index, 0);
  assert.deepEqual(artifact.handleNames, ["edit-0"]);
  assert.deepEqual(artifact.commitKinds, ["Undo"]);
  assert.deepEqual(artifact.settlements, ["FullyApplied"]);
  assert.equal(artifact.eventTrace.length, 1);
});

test("sequence refusals require distinct diagnostics and a stopped document", async () => {
  const { expected, report } = await validFixture();
  const diagnostics = new Map([
    ["malformed-sequence-payload",
      "message.changeset[0].data.changes[0].change expected an array"],
    ["malformed-range-count",
      "message.changeset[0].data.changes[0].change[0].count expected a positive integer"],
    ["missing-range-endpoint",
      "message.changeset[0].data.changes[0].change[0].effect.moveIn.finalEndpoint atom"],
    ["bad-child-ownership", "cross-field ownership owned ranges overlap"],
    ["invalid-sequence-content",
      "message.changeset[0].data.changes[0].change[0].changes unknown property content"],
  ]);
  const cases = report.failures.filter(({ target, caseId }) =>
    target === "javascript" && diagnostics.has(caseId));
  assert.equal(cases.length, diagnostics.size);
  for (const item of cases) {
    item.typedError.message = diagnostics.get(item.caseId);
    assert.equal(item.clientState, "stopped-after-ready", item.caseId);
    assert.equal(item.writableTreeExposedAfterRefusal, false, item.caseId);
  }
  assert.equal(validateInteropReport(report, expected), report);

  for (const item of cases) {
    const diagnostic = item.typedError.message;
    item.typedError.message =
      "message.changeset[0] change must contain exactly one data or schema member";
    assert.throws(
      () => validateInteropReport(report, expected),
      /Failure diagnostic lacks source reason or location/,
      item.caseId,
    );
    item.typedError.message = diagnostic;
  }
});

test("deterministic service order ignores submissions before each authored prefix", async () => {
  const { expected, report } = await validFixture();
  const item = report.deterministic.find(
    ({ id }) => id === "array-same-gap-insert:upstream->javascript:javascript-first",
  );
  item.evidence.submissions.unshift({
    author: "upstream",
    outerSequenceNumber: 7,
    innerIndex: 0,
    referenceSequenceNumber: 6,
    revision: 99,
    originatorId: "bootstrap-upstream",
    allocations: [],
  });
  const claim = expected.artifacts.get(item.artifacts[0]).claim;
  claim.measured.evidence = structuredClone(item.evidence);
  assert.equal(validateInteropReport(report, expected), report);
});

test("array move families require exact retained object survival", async () => {
  for (const [id, retainedObjectReferences] of [
    ["array-move-child-edit:upstream->javascript:upstream-first", [false, false]],
    ["array-move-delete:upstream->javascript:javascript-first", [false, false]],
    ["array-move-delete:upstream->javascript:upstream-first", [true, true]],
  ]) {
    const { expected, report } = await validFixture();
    const item = report.deterministic.find((candidate) => candidate.id === id);
    item.evidence.array.retainedObjectReferences = retainedObjectReferences;
    expected.artifacts.get(item.artifacts[0]).claim.measured.evidence =
      structuredClone(item.evidence);
    assert.throws(
      () => validateInteropReport(report, expected),
      /retained object references/i,
      id,
    );
  }
});

test("the acceptance report requires all nine map reload cells", async () => {
  const { expected, report } = await validFixture();
  delete report.mapReload.upstream.javascript;
  assert.throws(() => validateInteropReport(report, expected),
    /map summary interop needs all three readers/i);
});

test("the acceptance report requires every schema section", async () => {
  for (const section of [
    "schemaCompatibility",
    "schemaRaces",
    "schemaReconnect",
    "schemaReloadMatrix",
    "schemaTailReloadMatrix",
  ]) {
    const { expected, report } = await validFixture();
    delete report[section];
    assert.throws(
      () => validateInteropReport(report, expected),
      new RegExp(section),
    );
  }
});

test("schema sections reject missing coverage and empty observations", async () => {
  for (const [label, mutate] of [
    ["missing target", (report) => report.schemaCompatibility.pop()],
    ["missing race ordering", (report) => {
      report.schemaRaces = report.schemaRaces.filter(
        ({ family, order }) =>
          !(family === "schema-data" && order === "competitor-first"),
      );
    }],
    ["missing writer reader cell", (report) => {
      delete report.schemaReloadMatrix.javascript.erlang;
    }],
    ["zero observations", (report) => {
      report.schemaReconnect[0].observations = [];
    }],
    ["skipped required cell", (report) => {
      report.schemaReloadMatrix.erlang.upstream.skipped = true;
    }],
  ]) {
    const { expected, report } = await validFixture();
    mutate(report);
    assert.throws(() => validateInteropReport(report, expected), undefined, label);
  }
});

test("schema evidence rejects missing, mismatched, and contradictory artifacts", async () => {
  {
    const { expected, report } = await validFixture();
    report.schemaRaces[0].artifacts = ["evidence/does-not-exist.json"];
    assert.throws(() => validateInteropReport(report, expected),
      /unverified artifact/i);
  }
  for (const [label, mutate] of [
    ["run", (claim) => { claim.runId = "another-run"; }],
    ["subject", (claim) => { claim.subject = "another-subject"; }],
    ["document", (claim) => { claim.documentId = "another-document"; }],
    ["result", (claim) => {
      claim.result.observations[0].documentHealthy = false;
    }],
  ]) {
    const { artifacts, expected, owned, report } = await validFixture();
    const references = [...artifacts.keys()];
    const reference = report.schemaRaces.find(
      ({ family }) => family === "schema-schema",
    ).artifacts[0];
    const claim = structuredClone(artifacts.get(reference).claim);
    mutate(claim);
    await writeFile(join(owned, reference), `${JSON.stringify(claim)}\n`);
    const evidence = await createArtifactEvidence(owned, references);
    assert.throws(() => validateInteropReport(report, {
      ...expected,
      artifacts: evidence,
    }), undefined, label);
  }
});

test("schema evidence requires substantive checkpoints and identities", async () => {
  for (const [label, mutate] of [
    ["rollback checkpoint", (report) => {
      delete report.schemaRaces.find(
        ({ family }) => family === "schema-schema",
      ).observations[0].rollback;
    }],
    ["reconnect revisions", (report) => {
      report.schemaReconnect[0].observations[0].originalRevisions = [];
    }],
    ["reload version", (report) => {
      delete report.schemaReloadMatrix.upstream.javascript
        .observations[0].loadedVersion;
    }],
    ["reload instance", (report) => {
      delete report.schemaReloadMatrix.upstream.javascript
        .observations[0].readerInstanceId;
    }],
    ["contradictory stored schema", (report) => {
      report.schemaReloadMatrix.upstream.javascript
        .observations[0].pendingStoredState.schema.content = "{\"wrong\":true}";
    }],
  ]) {
    const { expected, report } = await validFixture();
    mutate(report);
    assert.throws(() => validateInteropReport(report, expected), undefined, label);
  }
});

test("schema validators reject coordinated report and artifact false positives", async () => {
  for (const [label, select, mutate] of [
    ["empty accepted reconnect commits", (report) => report.schemaReconnect[0],
      (observation) => { observation.acceptedCommits = []; }],
    ["wrong reconnect original operation", (report) => report.schemaReconnect[0],
      (observation) => {
        observation.originalOperations[1].payload[0].data.value = 999;
      }],
    ["fictitious reconnect mapping", (report) => report.schemaReconnect[0],
      (observation) => {
        observation.acceptedMappings[0].acceptedRevision = "invented";
      }],
    ["erased reconnect changesets", (report) => report.schemaReconnect[0],
      (observation) => {
        observation.acceptedCommits[0].changeset = [];
        observation.acceptedCommits[1].changeset = [];
      }],
    ["rollback payload is not empty",
      (report) => report.schemaRaces.find(({ family }) => family === "schema-schema"),
      (observation) => {
        const loser = observation.rollback.observations.find(
          ({ implementation }) => implementation === observation.losingAuthor,
        );
        loser.history.pending[0].changeset.raw =
          { changes: [{ type: "data", innerChange: { invented: true } }] };
      }],
    ["empty fresh reader history",
      (report) => report.schemaReloadMatrix.upstream.javascript,
      (observation) => { observation.freshLoadCheckpoint.history.trunk = []; }],
    ["wrong retained peer",
      (report) => report.schemaReloadMatrix.upstream.javascript,
      (observation) => { observation.retainedPeerAuthor = "erlang"; }],
    ["wrong pending operation",
      (report) => report.schemaReloadMatrix.upstream.javascript,
      (observation) => {
        observation.pendingWriterCheckpoint.history.pending[0] = {
          revision: "wrong",
          originatorId: "wrong",
          changeset: { changeCount: 1, raw: { changes: [{ type: "data" }] } },
        };
      }],
    ["unrelated tree request",
      (report) => report.schemaReloadMatrix.upstream.javascript,
      (observation) => { observation.selectedTreeRequests = ["unrelated-tree"]; }],
    ["unrelated blob request",
      (report) => report.schemaReloadMatrix.upstream.javascript,
      (observation) => { observation.selectedBlobRequests = ["unrelated-blob"]; }],
  ]) {
    const { expected, owned, report } = await validFixture();
    const item = select(report);
    const observation = item.observations[0];
    mutate(observation);
    for (const reference of item.artifacts) {
      const claim = structuredClone(expected.artifacts.get(reference).claim);
      claim.result = item.writer === undefined
        ? structuredClone(observation)
        : Object.fromEntries(Object.entries(structuredClone(item))
          .filter(([name]) => name !== "artifacts"));
      await writeFile(join(owned, reference), `${JSON.stringify(claim)}\n`);
    }
    const artifacts = await createArtifactEvidence(
      owned,
      [...expected.artifacts.keys()],
    );
    assert.throws(() => validateInteropReport(report, {
      ...expected,
      artifacts,
    }), undefined, label);
  }
});

for (const [label, changeset] of [
  ["empty raw history", { changeCount: 1, raw: [] }],
  ["invented structured history", {
    changeCount: 1,
    raw: { changes: [{ type: "invented" }] },
  }],
  ["invented textual history", {
    changeCount: 1,
    raw: "Changeset([DataChange(invented)])",
  }],
  ["unknown nested textual constructors", {
    changeCount: 1,
    raw: 'Changeset([DataChange(Changeset(ChangeData('
      + 'Invented(#("score", OptionalField(Bogus())), NumberValue(1000))'
      + ")))])",
  }],
  ["fabricated native constructor shortcuts", {
    changeCount: 1,
    raw: 'Changeset([DataChange(Changeset(ChangeData('
      + '[#("score", OptionalField(FieldChange()))], '
      + '[Build(AtomId(0), [NumberValue(1000)])])))])',
  }],
  ["history count mismatch", {
    changeCount: 2,
    raw: {
      changes: [{
        type: "schema",
        innerChange: { schema: { old: {}, new: { upgraded: true } } },
      }],
    },
  }],
]) {
  test(`post-upgrade reload rejects ${label}`, async () => {
    const { expected, owned, report } = await validFixture();
    const item = report.schemaReloadMatrix.upstream.javascript;
    const observation = item.observations[0];
    observation.freshLoadCheckpoint.history.trunk[0] = {
      revision: "invented",
      originatorId: "invented",
      changeset,
    };
    observation.beforeContinuation.history.trunk[0] =
      structuredClone(observation.freshLoadCheckpoint.history.trunk[0]);
    for (const reference of item.artifacts) {
      const claim = structuredClone(expected.artifacts.get(reference).claim);
      claim.result = Object.fromEntries(Object.entries(structuredClone(item))
        .filter(([name]) => name !== "artifacts"));
      await writeFile(join(owned, reference), `${JSON.stringify(claim)}\n`);
    }
    const artifacts = await createArtifactEvidence(
      owned,
      [...expected.artifacts.keys()],
    );
    assert.throws(
      () => validateInteropReport(report, { ...expected, artifacts }),
      {
        name: "AssertionError",
        message: /post-upgrade fresh-reader history contains an? (?:empty|invalid|mismatched) operation/i,
      },
    );
  });
}

test("the acceptance report requires all nine array reload cells", async () => {
  const { expected, report } = await validFixture();
  delete report.arrayReload.upstream.javascript;
  assert.throws(() => validateInteropReport(report, expected),
    /array summary interop needs all three readers/i);
});

test("array scenarios cannot bypass evidence checks by changing profile", async () => {
  const { expected, report } = await validFixture();
  const item = report.deterministic.find(
    ({ id }) => id === "array-move-child-edit:upstream->javascript:upstream-first",
  );
  item.profile = "object";
  item.evidence.array.retainedObjectReferences = [false, false];
  expected.artifacts.get(item.artifacts[0]).claim.measured.evidence =
    structuredClone(item.evidence);
  assert.throws(
    () => validateInteropReport(report, expected),
    /deterministic profile changed/i,
  );
});

test("the acceptance report rejects one missing required array scenario cell", async () => {
  const { expected, report } = await validFixture();
  const index = report.deterministic.findIndex(({ profile }) => profile === "array");
  assert(index >= 0);
  report.deterministic.splice(index, 1);
  assert.throws(() => validateInteropReport(report, expected),
    /deterministic results/i);
});

test("single-author algebra cells do not invent pending state", async () => {
  const { expected, report } = await validFixture();
  const item = report.deterministic.find(
    ({ id }) => id === "optional-set-clear:repeated-clear:upstream",
  );
  const optimistic = item.checkpoints.find(({ stage }) => stage === "intermediate");
  for (const observation of optimistic.observations) {
    observation.pendingTreeCount = 0;
    observation.inflightSubmissionCount = 0;
  }
  const claim = expected.artifacts.get(item.artifacts[0]).claim;
  claim.measured.checkpoints = structuredClone(item.checkpoints);
  assert.equal(validateInteropReport(report, expected), report);
});

test("only native detached authors require two distinct refreshers", async () => {
  const { expected, report } = await validFixture();
  const item = report.deterministic.find(
    ({ id }) => id === "detached-child-reconciliation:upstream",
  );
  item.evidence.retained.refreshers = [[1, 2]];
  const optimistic = item.checkpoints.find(({ stage }) => stage === "intermediate");
  for (const observation of optimistic.observations) {
    observation.pendingTreeCount = 0;
    observation.inflightSubmissionCount = 0;
  }
  const upstream = optimistic.observations.find(
    ({ implementation }) => implementation === "upstream",
  );
  upstream.inflightSubmissionCount = 1;
  const claim = expected.artifacts.get(item.artifacts[0]).claim;
  claim.measured.checkpoints = structuredClone(item.checkpoints);
  claim.measured.evidence = structuredClone(item.evidence);
  assert.equal(validateInteropReport(report, expected), report);
});

test("decoded submissions require native batch IDs without inventing upstream IDs", async () => {
  const { expected, report } = await validFixture();
  const item = report.deterministic.find(
    ({ id }) => id === "independent-scalar:upstream->javascript",
  );
  const upstream = item.evidence.submissions.find(
    ({ author }) => author === "upstream",
  );
  delete upstream.batchId;
  const claim = expected.artifacts.get(item.artifacts[0]).claim;
  claim.measured.evidence = structuredClone(item.evidence);
  assert.equal(validateInteropReport(report, expected), report);

  const native = item.evidence.submissions.find(
    ({ author }) => author === "javascript",
  );
  delete native.batchId;
  claim.measured.evidence = structuredClone(item.evidence);
  assert.throws(() => validateInteropReport(report, expected));
});

test("grouped commit indexes stay consecutive after allocation entries", async () => {
  const { expected, report } = await validFixture();
  const item = report.deterministic.find(
    ({ family, authors }) =>
      family === "grouped-commits" && authors[0] === "upstream",
  );
  const claim = expected.artifacts.get(item.artifacts[0]).claim;
  claim.measured.evidence = structuredClone(item.evidence);
  assert.equal(validateInteropReport(report, expected), report);

  item.evidence.grouped.commits.forEach((commit, index) => {
    commit.innerIndex = index;
  });
  claim.measured.evidence = structuredClone(item.evidence);
  assert.throws(() => validateInteropReport(report, expected));

  item.evidence.grouped.commits.forEach((commit, index) => {
    commit.innerIndex = index + 1;
  });
  item.evidence.grouped.commits[1].innerIndex = 3;
  claim.measured.evidence = structuredClone(item.evidence);
  assert.throws(() => validateInteropReport(report, expected));
});

test("seeded evidence requires actual identities and accepted submissions", async () => {
  for (const mutation of ["identity", "submission"]) {
    const { expected, report } = await validFixture();
    const item = report.seeded[0];
    const claim = expected.artifacts.get(item.artifacts[0]).claim.measured;
    if (mutation === "identity") {
      delete item.identityMapping.erlang;
      delete claim.identityMapping.erlang;
    } else {
      item.evidence.submissions = item.evidence.submissions.filter(
        ({ author }) => author !== "erlang",
      );
      claim.evidence.submissions = structuredClone(item.evidence.submissions);
    }
    assert.throws(() => validateInteropReport(report, expected), undefined, mutation);
  }
});

test("seeded release evidence matches every generated action and sequenced commit", async () => {
  for (const [name, mutate] of [
    ["missing release", (item) => { item.evidence.releases.pop(); }],
    ["changed action order", (item) => { item.evidence.releases[0].order = "reverse"; }],
    ["unknown accepted sequence", (item) => {
      item.evidence.releases.find(({ direction }) => direction === "outbound")
        .acceptedSequenceNumbers = [999];
    }],
    ["wrong accepted commit count", (item) => {
      item.evidence.releases.find(({ direction }) => direction === "outbound")
        .acceptedCommitCount = 2;
    }],
    ["release before prior acceptance", (item) => {
      const outbound = item.evidence.releases.filter(
        ({ direction }) => direction === "outbound",
      );
      outbound[1].afterSequence = outbound[0].acceptedSequenceNumbers[0] - 1;
    }],
    ["native omitted delivered sequence", (item) => {
      item.evidence.releases.find(({ direction, author }) =>
        direction === "inbound" && author !== "upstream")
        .deliveredSequenceNumbers.pop();
    }],
    ["upstream did not receive accepted sequence", (item) => {
      item.evidence.releases.find(({ direction, author }) =>
        direction === "inbound" && author === "upstream")
        .receivedThrough = 0;
    }],
  ]) {
    const { expected, report } = await validFixture();
    const item = report.seeded.find(({ actions }) =>
      actions.some(({ type, direction, author }) =>
        type === "release" && direction === "inbound" && author === "upstream"));
    mutate(item);
    const claim = expected.artifacts.get(item.artifacts[0]).claim;
    claim.measured.evidence = structuredClone(item.evidence);
    assert.throws(() => validateInteropReport(report, expected), undefined, name);
  }
});

test("reload retained evidence contains the restored detached point", async () => {
  const { expected, report } = await validFixture();
  const item = report.reload.upstream.javascript;
  item.retained.removed[0][2].fields.x[0].value = 41;
  const claim = expected.artifacts.get(item.artifacts[0]).claim;
  claim.measured.retained.removed[0][2].fields.x[0].value = 41;
  assert.throws(() => validateInteropReport(report, expected));
});

test("reload evidence proves applied native replay and resubmission identity", async () => {
  {
    const { expected, report } = await validFixture();
    const item = report.reload.upstream.javascript;
    const claim = expected.artifacts.get(item.artifacts[0]).claim;
    claim.raw.load.handshakes[0].initialMessageSequenceNumbers =
      [1, item.snapshotSequenceNumber];
    assert.throws(() => validateInteropReport(report, expected));
  }
  {
    const { expected, report } = await validFixture();
    const item = report.reload.javascript.upstream;
    delete item.retained.writerIdentity.resubmissions[0].referenceSequenceNumber;
    const claim = expected.artifacts.get(item.artifacts[0]).claim;
    delete claim.measured.retained.writerIdentity.resubmissions[0]
      .referenceSequenceNumber;
    assert.throws(() => validateInteropReport(report, expected));
  }
});

test("partial, stale, and synthetic-shaped evidence cannot pass", async () => {
  const { expected, report } = await validFixture();
  const mutations = [
    ["missing deterministic cell", (copy) => copy.deterministic.pop()],
    ["duplicate deterministic cell", (copy) => {
      copy.deterministic[1] = structuredClone(copy.deterministic[0]);
    }],
    ["unknown deterministic cell", (copy) => {
      copy.deterministic[0].id = "unknown";
    }],
    ["stale run", (copy) => { copy.runId = "stale"; }],
    ["wrong profile", (copy) => {
      copy.profile.container.runtimeOptions.enableRuntimeIdCompressor = "off";
    }],
    ["wrong reference pin", (copy) => { copy.reference.version = "3.2.0"; }],
    ["wrong service pin", (copy) => { copy.service.revision = "stale"; }],
    ["stale service evidence", (copy) => { copy.service.runId = "stale"; }],
    ["absent native target", (copy) => { delete copy.corpus.erlang; }],
    ["reused reload reader", (copy) => {
      copy.reload.javascript.erlang.readerInstanceId =
        copy.reload.javascript.javascript.readerInstanceId;
    }],
    ["wrong loaded version", (copy) => {
      copy.reload.upstream.javascript.loadedVersion = "other";
    }],
    ["missing selected summary consumption", (copy) => {
      copy.reload.upstream.javascript.selectedSummaryRequests = [];
    }],
    ["missing tail", (copy) => {
      copy.reload.upstream.javascript.dataEditSequenceNumber =
        copy.reload.upstream.javascript.snapshotSequenceNumber;
    }],
    ["no continuation peer", (copy) => {
      copy.reload.upstream.javascript.peerObservedEdit = false;
    }],
    ["origin replay", (copy) => {
      copy.reload.upstream.javascript.replayStartSequenceNumber = 0;
    }],
    ["writer head changed", (copy) => {
      copy.reload.upstream.javascript.writerVersionAfterLoad = "other";
    }],
    ["missing retained identity", (copy) => {
      delete copy.reload.upstream.javascript.retained.writerIdentity;
    }],
    ["reload artifact measured payload differs", (copy, fixtureExpected) => {
      const reference = copy.reload.upstream.javascript.artifacts[0];
      fixtureExpected.artifacts.get(reference).claim.measured.loadedVersion = "other";
    }],
    ["nonzero pending count", (copy) => {
      copy.seeded[0].checkpoints.find(({ label }) => label === "settled")
        .observations[0].pendingTreeCount = 1;
    }],
    ["skip", (copy) => { copy.skipped.push("seeded:0"); }],
    ["divergence", (copy) => { copy.divergences.push({ path: "$.title" }); }],
    ["omitted intermediate observation", (copy) => {
      copy.deterministic[0].checkpoints =
        copy.deterministic[0].checkpoints.filter(({ stage }) => stage !== "intermediate");
    }],
    ["omitted initial common barrier", (copy) => {
      copy.deterministic[0].checkpoints =
        copy.deterministic[0].checkpoints.filter(({ label }) => label !== "initial");
    }],
    ["omitted whole tree", (copy) => {
      delete copy.deterministic[0].checkpoints[0].observations[0].wholeTree;
    }],
    ["omitted reconnect retry trace", (copy) => {
      const observation = copy.deterministic[0].checkpoints[0].observations.find(
        ({ implementation }) => implementation !== "upstream",
      );
      delete observation.reconnectRetries;
    }],
    ["zero corpus execution", (copy) => {
      copy.corpus.javascript.executedCount = 0;
    }],
    ["wrong corpus command", (_copy, expected) => {
      const artifact = expected.artifacts.get("evidence/corpus-javascript.json");
      artifact.claim.command = [
        "gleam", "test", "--target", "javascript",
        "--test-name-filter=shared_tree",
      ];
    }],
    ["unsanitized raw reconnect retry trace", (copy, expected) => {
      const artifact = expected.artifacts.get(copy.deterministic[0].artifacts[0]);
      artifact.claim.raw.gates.javascript.reconnectRetries = [{
        attempt: 1,
        code: "connection-failed",
        operation: "await-synced",
        message: "channel connect failed: Transport(Timeout)",
        stack: "secret path",
      }];
    }],
    ["changed reconnect retry trace", (copy, expected) => {
      const item = copy.deterministic[0];
      const timeout = {
        attempt: 1,
        code: "connection-failed",
        operation: "await-synced",
        message: "channel connect failed: Transport(Timeout)",
      };
      const closed = {
        ...timeout,
        message: 'channel connect failed: Transport(StreamError("Closed"))',
      };
      item.checkpoints[1].observations.find(
        ({ implementation }) => implementation === "javascript",
      ).reconnectRetries = [timeout];
      item.checkpoints[2].observations.find(
        ({ implementation }) => implementation === "javascript",
      ).reconnectRetries = [closed];
      const artifact = expected.artifacts.get(item.artifacts[0]).claim;
      artifact.measured.checkpoints = structuredClone(item.checkpoints);
      artifact.raw.gates.javascript.reconnectRetries = [closed];
    }],
    ["missing decoded allocation", (copy) => {
      for (const submission of copy.deterministic[0].evidence.submissions) {
        submission.allocations = [];
      }
    }],
    ["collapsed grouped commits", (copy) => {
      copy.deterministic.find(({ family, authors }) =>
        family === "grouped-commits" && authors[0] === "upstream")
        .evidence.grouped.commits = [{ innerIndex: 0, revision: 0, originatorId: "upstream" }];
    }],
    ["missing retained observation", (copy) => {
      delete copy.deterministic.find(
        ({ family }) => family === "detached-child-reconciliation",
      ).evidence.retained;
    }],
    ["artifact measured payload differs", (copy, fixtureExpected) => {
      const reference = copy.deterministic[0].artifacts[0];
      fixtureExpected.artifacts.get(reference).claim.measured.authorCoverage = [];
    }],
    ["duplicate seeded index", (copy) => { copy.seeded[1].index = 0; }],
    ["fewer seeded schedules", (copy) => { copy.seeded.pop(); }],
    ["incomplete seeded producer", (copy) => {
      copy.seededAccounting.executed = 299;
    }],
    ["missing seeded accounting", (copy) => {
      delete copy.seededAccounting;
    }],
    ["missing measured author", (copy) => {
      copy.seeded[0].authorCoverage = ["upstream", "javascript"];
    }],
    ["missing seeded identity", (copy, fixtureExpected) => {
      delete copy.seeded[0].identityMapping.erlang;
      const reference = copy.seeded[0].artifacts[0];
      delete fixtureExpected.artifacts.get(reference).claim.measured
        .identityMapping.erlang;
    }],
    ["missing seeded accepted submission", (copy, fixtureExpected) => {
      copy.seeded[0].evidence.submissions =
        copy.seeded[0].evidence.submissions.filter(
          ({ author }) => author !== "erlang",
        );
      const reference = copy.seeded[0].artifacts[0];
      fixtureExpected.artifacts.get(reference).claim.measured.evidence.submissions =
        structuredClone(copy.seeded[0].evidence.submissions);
    }],
    ["changed seeded expansion", (copy) => {
      copy.seeded[0].actions = [{ type: "checkpoint" }];
    }],
    ["stale seeded artifact", (copy, fixtureExpected) => {
      const reference = copy.seeded[0].artifacts[0];
      fixtureExpected.artifacts.get(reference).claim.measured.seed = 43;
    }],
    ["missing artifact", (copy) => {
      copy.deterministic[0].artifacts = ["evidence/missing.json"];
    }],
    ["irrelevant artifact", (copy) => {
      copy.deterministic[0].artifacts = copy.seeded[0].artifacts;
    }],
    ["wrong failure stage", (copy) => {
      copy.failures[0].stage = "summary-load";
    }],
    ["wrong failure code", (copy) => {
      copy.failures[0].typedError.code = "other";
    }],
    ["unrelated failure diagnostic", (copy) => {
      copy.failures[0].typedError.message = "unavailable service";
    }],
    ["wrong refusal client state", (copy) => {
      copy.failures[0].clientState = "never-ready";
    }],
    ["local refusal emitted an event", (copy) => {
      copy.failures[0].after.events.push({ kind: "changed" });
    }],
    ["partial local refusal", (copy) => {
      copy.failures[0].after.root.title = "changed";
    }],
  ];
  for (const [name, mutate] of mutations) {
    const copy = structuredClone(report);
    const expectedCopy = {
      ...expected,
      artifacts: new Map([...expected.artifacts].map(([reference, artifact]) =>
        [reference, structuredClone(artifact)])),
    };
    mutate(copy, expectedCopy);
    assert.throws(() => validateInteropReport(copy, expectedCopy), undefined, name);
  }
  assert.throws(() => validateInteropReport(report, {
    ...expected,
    artifacts: new Map([[report.service.preflightArtifact, {
      path: join(expected.artifactDirectory, report.service.preflightArtifact),
      size: 20,
    }]]),
  }), /verified artifact evidence/);
});

test("artifact evidence is nonempty, regular, and contained by the owned root", async () => {
  const owned = await mkdtemp(join(tmpdir(), "watershed-artifacts-"));
  const outside = join(await mkdtemp(join(tmpdir(), "watershed-outside-")), "outside.json");
  await writeFile(outside, "{}");
  await writeFile(join(owned, "empty.json"), "");
  await symlink(outside, join(owned, "escape.json"));
  await assert.rejects(() => createArtifactEvidence(owned, ["../outside.json"]));
  await assert.rejects(() => createArtifactEvidence(owned, ["empty.json"]));
  await assert.rejects(() => createArtifactEvidence(owned, ["escape.json"]));
});

test("the committed profile is hashed and every compatibility pin is validated", async () => {
  const loaded = await loadInteropProfile(profilePath);
  assert.match(loaded.profileDigest, /^[0-9a-f]{64}$/);
  assert.equal(
    loaded.profileDigest,
    "588a2f41621f4f352497915168a5dc8af55140721066a04f217ab03e639a1813",
  );
  assert.deepEqual(loaded.profile.reference, reference);
  assert.deepEqual(
    {
      implementation: loaded.profile.service.implementation,
      revision: loaded.profile.service.revision,
    },
    service,
  );
  assert.deepEqual(loaded.profile.supportedFeatures, [
    "fixed-object-schema",
    "primitive-leaves",
    "optional-string",
    "nested-object",
    "dynamic-map-schema",
    "per-key-map-edits",
    "recursive-map-values",
    "canonical-map-iteration",
    "bootstrap-map-handle",
    "recursive-array-values",
    "range-array-edits",
    "cross-array-moves",
    "identifier-fields",
    "identifier-defaults",
    "identifier-compression",
    "identifier-summary-reload",
    "grouped-batches",
    "gc-metadata",
    "strict-view-object-map-schema-evolution",
  ]);
  assert.deepEqual(loaded.profile.excludedFeatures, [
    "array-schema-evolution",
    "staged-schema-upgrades",
    "unknown-field-view-adapters",
    "data-migrations",
    "public-transactions",
    "additional-upstream-versions",
    "shared-branches",
    "gc-sweep",
    "compressed-ops",
    "chunked-ops",
    "identifier-handles",
    "incremental-field-batch-chunks",
    "arbitrary-container-layouts",
    "tree-short-id",
    "identifier-index",
    "custom-identifier-global-uniqueness",
    "detached-node-builder",
    "uuidv5-healing",
    "undo-redo",
    "async-cross-tree-transactions",
  ]);
  assert(!loaded.profile.excludedFeatures.includes("arrays"));
  assert(!loaded.profile.excludedFeatures.includes("maps-in-tree"));
  const directory = await mkdtemp(join(tmpdir(), "watershed-profile-"));
  const profile = JSON.parse(await readFile(profilePath, "utf8"));
  for (const [name, mutate] of [
    ["reference", (copy) => { copy.reference.commit = "stale"; }],
    ["service", (copy) => { copy.service.revision = "stale"; }],
    ["service-policy", (copy) => {
      copy.service.driverPolicies.enableRestLess = false;
    }],
    ["runtime", (copy) => {
      copy.container.runtimeOptions.enableRuntimeIdCompressor = "off";
    }],
    ["summarizer-runtime", (copy) => {
      copy.container.summarizerRuntimeOptions.summaryOptions
        .summaryConfigOverrides.maxAckWaitTime = 1;
    }],
    ["schema", (copy) => { copy.container.treePath = "/wrong"; }],
    ["codec", (copy) => { copy.codecTree.children[0].version = 3; }],
    ["compressor", (copy) => { copy.compressorFormat.byteOrder = "BE"; }],
  ]) {
    const copy = structuredClone(profile);
    mutate(copy);
    const path = join(directory, `${name}.json`);
    await writeFile(path, JSON.stringify(copy));
    await assert.rejects(() => loadInteropProfile(path));
  }
});

test("CLI options accept only bounded acceptance or replay invocations", () => {
  assert.deepEqual(parseInteropOptions([], { cwd: repository }), {
    mode: "acceptance",
    profilePath,
    iterations: 300,
    seed: 42,
    outputDirectory: join(repository, "tools/shared-tree-oracle/.output/interop"),
    replayPath: undefined,
    externalFloodgate: false,
  });
  assert.deepEqual(parseInteropOptions([
    "--profile", "test/fixtures/shared_tree/profile.json",
    "--iterations", "300",
    "--seed", "42",
    "--output", "artifacts",
    "--external-floodgate",
  ], { cwd: repository }), {
    mode: "acceptance",
    profilePath,
    iterations: 300,
    seed: 42,
    outputDirectory: join(repository, "artifacts"),
    replayPath: undefined,
    externalFloodgate: true,
  });
  assert.deepEqual(parseInteropOptions([], { cwd: oracleDirectory }), {
    mode: "acceptance",
    profilePath,
    iterations: 300,
    seed: 42,
    outputDirectory: join(repository, "tools/shared-tree-oracle/.output/interop"),
    replayPath: undefined,
    externalFloodgate: false,
  });
  assert.deepEqual(parseInteropOptions([
    "--replay", "failure.json",
    "--output", "artifacts",
  ], { cwd: repository }), {
    mode: "replay",
    profilePath: undefined,
    iterations: undefined,
    seed: undefined,
    outputDirectory: join(repository, "artifacts"),
    replayPath: join(repository, "failure.json"),
    externalFloodgate: false,
  });
  for (const args of [
    ["--profile", "profile.json", "--iterations", "299", "--seed", "42"],
    ["--profile", "profile.json", "--iterations", "0", "--seed", "42"],
    ["--profile", "profile.json", "--iterations", "-1", "--seed", "42"],
    ["--profile", "profile.json", "--iterations", "300.5", "--seed", "42"],
    ["--profile", "profile.json", "--iterations", "abc", "--seed", "42"],
    ["--profile", "profile.json", "--iterations", "300", "--seed", "-1"],
    ["--profile", "profile.json", "--iterations", "300", "--seed", "4294967296"],
    ["--profile", "profile.json", "--iterations", "300", "--seed", "1.5"],
    ["--profile", "profile.json", "--iterations", "300", "--seed", "42", "--unknown"],
    ["--replay", "failure.json", "--iterations", "300"],
    ["--replay", "failure.json", "--profile", "profile.json"],
    ["--replay", "failure.json", "--external-floodgate"],
  ]) {
    assert.throws(() => parseInteropOptions(args, { cwd: repository }));
  }
});

test("the coordinator routes parsed defaults to the acceptance gate", async () => {
  const calls = [];
  const output = [];
  await runInteropCommand([], {
    cwd: oracleDirectory,
    runAcceptance: async (options) => {
      calls.push(options);
      return { reportPath: "/tmp/report.json", runId: "fresh-run", report: { ok: true } };
    },
    stdout: { write: (value) => output.push(value) },
  });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].profilePath, profilePath);
  assert.equal(calls[0].iterations, 300);
  assert.equal(calls[0].seed, 42);
  assert.equal(calls[0].externalFloodgate, false);
  assert.deepEqual(JSON.parse(output.join("")), {
    reportPath: "/tmp/report.json",
    runId: "fresh-run",
    report: { ok: true },
  });
});

test("the coordinator prints specific and secondary diagnostic paths", async () => {
  const stderr = [];
  const error = Object.assign(new Error("seeded failure"), {
    failurePath: "/tmp/seeded-failure.json",
    coordinatorFailurePath: "/tmp/coordinator-failure.json",
  });
  await assert.rejects(() => runInteropCommand([], {
    cwd: oracleDirectory,
    runAcceptance: async () => { throw error; },
    stdout: { write() {} },
    stderr: { write: (value) => stderr.push(value) },
  }), (actual) => actual === error);
  assert.deepEqual(stderr, [
    "SharedTree interop failure: /tmp/seeded-failure.json\n",
    "SharedTree coordinator diagnostics: /tmp/coordinator-failure.json\n",
  ]);
});

test("corpus accounting accepts the current Gleam test summary", () => {
  const summary = [
    "Running 417 tests",
    "Test Files: 142",
    "     Tests: 417 passed (417)",
  ].join("\n");
  assert.equal(parseTestCount(summary, "javascript"), 417);
  assert.equal(parseTestCount(
    `\u001b[2m\u001b[37m     Tests: \u001b[39m\u001b[22m`
      + `\u001b[92m417 passed\u001b[39m \u001b[90m(417)\u001b[39m`,
    "javascript",
  ), 417);
});

test("native corpus accounting rejects empty and incomplete runs", () => {
  for (const output of [
    "Tests: 0 passed (0)",
    "Tests: 1 passed (2)",
    "1 tests, 1 failures",
    "No test summary was emitted",
  ]) {
    for (const target of ["javascript", "erlang"]) {
      assert.throws(() => parseTestCount(output, target));
    }
  }
});

test("preflight profile comparison preserves the JSON Infinity encoding", async () => {
  const loaded = await loadInteropProfile(profilePath);
  const captured = structuredClone(loaded.profile);
  captured.container.runtimeOptions.compressionOptions.minimumBatchSizeInBytes =
    Infinity;
  captured.container.summarizerRuntimeOptions.compressionOptions
    .minimumBatchSizeInBytes = Infinity;
  assert.doesNotThrow(() => assertPreflightProfile(captured, loaded.profile));
  captured.container.runtimeOptions.enableRuntimeIdCompressor = "off";
  assert.throws(() => assertPreflightProfile(captured, loaded.profile));
});
