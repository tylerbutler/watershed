import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";
import * as interop from "./interop.mjs";
import { caseIds } from "./client-interop.mjs";
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
  requiredFailureCells,
  requiredScenarioCells,
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
  const error = Object.assign(new Error("primary failure"), {
    code: "PRIMARY",
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
  const seeded = generateSchedules({ seed: 42, iterations: 200 })
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
    };
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
    iterations: 200,
    seededAccounting: {
      requested: 200,
      generated: 200,
      executed: 200,
      seed: 42,
    },
    deterministic,
    reconnect,
    failures,
    seeded,
    reload,
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
    iterations: 200,
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
    iterations: 200,
    deterministic: [],
    reconnect: [],
    failures: [],
    seeded: [],
    reload: {},
    corpus: {},
    skipped: [],
    divergences: [],
  }, expected));
});

test("a complete current-run report satisfies the Task 15 coverage gate", async () => {
  const { expected, report } = await validFixture();
  assert.equal(validateInteropReport(report, expected), report);
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
      copy.seededAccounting.executed = 199;
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
    "a13390fcfcb551c142eee272db78b18fa899e9f2e7dc608e2ca71be06fee8fc2",
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
    "grouped-batches",
    "gc-metadata",
  ]);
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
    iterations: 200,
    seed: 42,
    outputDirectory: join(repository, "tools/shared-tree-oracle/.output/interop"),
    replayPath: undefined,
    externalFloodgate: false,
  });
  assert.deepEqual(parseInteropOptions([
    "--profile", "test/fixtures/shared_tree/profile.json",
    "--iterations", "200",
    "--seed", "42",
    "--output", "artifacts",
    "--external-floodgate",
  ], { cwd: repository }), {
    mode: "acceptance",
    profilePath,
    iterations: 200,
    seed: 42,
    outputDirectory: join(repository, "artifacts"),
    replayPath: undefined,
    externalFloodgate: true,
  });
  assert.deepEqual(parseInteropOptions([], { cwd: oracleDirectory }), {
    mode: "acceptance",
    profilePath,
    iterations: 200,
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
    ["--profile", "profile.json", "--iterations", "199", "--seed", "42"],
    ["--profile", "profile.json", "--iterations", "0", "--seed", "42"],
    ["--profile", "profile.json", "--iterations", "-1", "--seed", "42"],
    ["--profile", "profile.json", "--iterations", "200.5", "--seed", "42"],
    ["--profile", "profile.json", "--iterations", "abc", "--seed", "42"],
    ["--profile", "profile.json", "--iterations", "200", "--seed", "-1"],
    ["--profile", "profile.json", "--iterations", "200", "--seed", "4294967296"],
    ["--profile", "profile.json", "--iterations", "200", "--seed", "1.5"],
    ["--profile", "profile.json", "--iterations", "200", "--seed", "42", "--unknown"],
    ["--replay", "failure.json", "--iterations", "200"],
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
  assert.equal(calls[0].iterations, 200);
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
