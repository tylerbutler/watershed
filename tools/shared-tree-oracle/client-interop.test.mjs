import assert from "node:assert/strict";
import test from "node:test";
import {
  caseIds,
  runService,
  transactionCaseIds,
  validateResults,
  validateTransactionReconnectResults,
} from "./client-interop.mjs";

const targets = ["javascript", "erlang"];
const valid = () => targets.flatMap((target) => caseIds.map((caseId) => ({
  target, caseId, runId: "one-run", profile: "fluid-3.1.0-fixed-object",
  documentId: `document-${target}-${caseId}`,
  passed: true, skipped: false,
  evidence: {
    sequenceNumber: 1, clientId: "client", pendingTreeCount: 0,
    ...(caseId === "detached-repair"
      ? { repairValues: [[1, 2], [42, 2]] } : {}),
    checkpoints: ["initial", "final"].map((label) => ({
      label, sequenceNumber: 1, clientId: "client",
      pendingTreeCount: 0, values: {}, events: [],
    })),
    submissions: [{
      sequenceNumber: 1, batchId: "batch", revision: 1,
      originatorId: "native",
    }],
  },
})));

test("an absent target or empty result set cannot pass", () => {
  assert.throws(() => validateResults([]));
  assert.throws(() => validateResults(valid().filter(({ target }) => target === "javascript")));
});

test("twelve measured cases pass only with one run and the fixed profile", () => {
  assert.equal(validateResults(valid(), "one-run").length, 12);
  for (const mutation of [
    (results) => results.push({ ...results[0] }),
    (results) => { results[0].caseId = "unexpected"; },
    (results) => { results[0].passed = false; },
    (results) => { results[0].skipped = true; },
    (results) => { results[0].runId = "stale"; },
    (results) => { results[0].profile = "other"; },
    (results) => { delete results[0].documentId; },
    (results) => { results[0].evidence = {}; },
    (results) => { results[0].runId = ""; },
    (results) => { results[0].evidence.submissions = []; },
    (results) => {
      delete results.find(({ caseId }) => caseId === "detached-repair")
        .evidence.repairValues;
    },
  ]) {
    const results = valid();
    mutation(results);
    assert.throws(() => validateResults(results, "one-run"));
  }
});

const validTransaction = () => targets.flatMap((target) =>
  transactionCaseIds.map((caseId) => ({
    target,
    caseId,
    runId: "one-run",
    profile: "fluid-3.1.0-fixed-object",
    documentId: `document-${target}-${caseId}`,
    passed: true,
    skipped: false,
    evidence: {
      sequenceNumber: 4,
      clientId: "client",
      pendingTreeCount: 0,
      transaction: {
        committed: {
          outcome: "committed",
          outboundCount: 1,
          localEventCount: 1,
          nestedScopes: 1,
          editsApplied: 2,
          commitRevision: "revision",
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
        label, sequenceNumber: 4, clientId: "client",
        pendingTreeCount: 0, values: {}, events: [],
      })),
      submissions: [{
        sequenceNumber: 4, batchId: "batch", revision: 1,
        originatorId: "native",
      }],
    },
  })));

test("transaction reconnect requires one resubmitted commit for every native target", () => {
  assert.equal(
    validateTransactionReconnectResults(validTransaction(), "one-run").length,
    targets.length * transactionCaseIds.length,
  );
  for (const [label, mutation] of [
    ["missing target", (results) => results.pop()],
    ["another run", (results) => { results[0].runId = "other-run"; }],
    ["failed case", (results) => { results[0].passed = false; }],
    ["lost commit", (results) => {
      results[0].evidence.transaction.resubmittedCommitCount = 0;
    }],
    ["duplicated commit", (results) => {
      results[1].evidence.transaction.resubmittedCommitCount = 2;
    }],
    ["unheld transaction", (results) => {
      results[0].evidence.transaction.pendingTreeCountWhileHeld = 0;
    }],
    ["leaked abort", (results) => {
      results[1].evidence.transaction.abortPeerObserved = true;
    }],
    ["abort event", (results) => {
      results[0].evidence.transaction.aborted.localEventCount = 1;
    }],
    ["split commit", (results) => {
      results[1].evidence.transaction.committed.outboundCount = 2;
    }],
    ["missing nested scope", (results) => {
      results[0].evidence.transaction.committed.nestedScopes = 0;
    }],
    ["absent transaction evidence", (results) => {
      delete results[0].evidence.transaction;
    }],
  ]) {
    const results = validTransaction();
    mutation(results);
    assert.throws(
      () => validateTransactionReconnectResults(results, "one-run"),
      undefined,
      label,
    );
  }
});

test("the focused runner exposes the combined-run options contract", () => {
  assert.equal(typeof runService, "function");
  assert.equal(runService.length, 1);
});
