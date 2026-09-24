import assert from "node:assert/strict";
import test from "node:test";
import { caseIds, validateResults } from "./client-interop.mjs";

const targets = ["javascript", "erlang"];
const valid = () => targets.flatMap((target) => caseIds.map((caseId) => ({
  target, caseId, runId: "one-run", profile: "fluid-3.1.0-fixed-object",
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
