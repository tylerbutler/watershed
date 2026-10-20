import assert from "node:assert/strict";
import test from "node:test";
import { summarize, validateReport, verdict } from "../lib/report.mjs";

const contract = {
  version: 1,
  task: "incident-response-board",
  groups: [
    { id: "local", description: "Local edits" },
    { id: "collaboration", description: "Live collaboration" },
  ],
  checks: [
    { id: "local.create", group: "local", requirement: "Create an incident." },
    { id: "local.assignee-remove", group: "local", requirement: "Remove an assignee." },
    { id: "collaboration.remote", group: "collaboration", requirement: "Observe remote edits." },
  ],
};

function report(overrides = {}) {
  return {
    version: 1,
    runId: "watershed-0001",
    sdk: "watershed",
    classification: "agent",
    checks: [
      { id: "local.create", passed: true, durationMs: 2, evidence: "Incident appeared" },
      { id: "local.assignee-remove", passed: true, durationMs: 3, evidence: "Assignee absent" },
      { id: "collaboration.remote", passed: true, durationMs: 4, evidence: "Remote title appeared" },
    ],
    ...overrides,
  };
}

test("requires all checks rather than accepting a passing subset", () => {
  assert.throws(() => validateReport(report({
    checks: report().checks.slice(0, 2),
  }), contract), /missing.*collaboration\.remote/i);
});

test("rejects duplicate and unknown check IDs", () => {
  const checks = report().checks;
  assert.throws(() => validateReport(report({
    checks: [...checks, checks[0]],
  }), contract), /duplicate/i);
  assert.throws(() => validateReport(report({
    checks: [...checks, { ...checks[0], id: "local.unregistered" }],
  }), contract), /unknown/i);
});

test("rejects malformed results instead of coercing a passing outcome", () => {
  for (const changed of [
    { passed: "true" },
    { passed: null },
    { durationMs: -1 },
    { durationMs: Number.NaN },
    { durationMs: Number.POSITIVE_INFINITY },
    { durationMs: "4" },
    { passed: false, evidence: "" },
    { passed: false, evidence: " " },
    { passed: true, evidence: null },
    { pass: true },
  ]) {
    const value = report();
    value.checks[0] = { ...value.checks[0], ...changed };
    assert.throws(() => validateReport(value, contract), TypeError);
  }
  for (const changed of [
    { version: 2 },
    { sdk: "other" },
    { runId: "" },
    { classification: "unknown" },
    { checks: null },
    { skipped: true },
  ]) {
    assert.throws(() => validateReport(report(changed), contract), TypeError);
  }
  assert.throws(() => validateReport(null, contract), TypeError);
});

test("one required collaboration failure fails the whole trial", () => {
  const value = report();
  value.checks[2] = {
    ...value.checks[2], passed: false, evidence: "Remote title never appeared",
  };
  assert.equal(verdict(value, contract), "failed");
  assert.equal(verdict(report(), contract), "passed");
});

test("infrastructure outcomes stay invalid even when every check passed", () => {
  assert.equal(verdict(report({ classification: "infrastructure" }), contract), "invalid");
});

test("summaries keep invalid trials out of agent pass-rate denominators", () => {
  const failed = report({ runId: "watershed-0002" });
  failed.checks[2] = { ...failed.checks[2], passed: false, evidence: "No remote update" };
  const result = summarize([
    report(),
    failed,
    report({ runId: "watershed-0003", classification: "infrastructure" }),
    report({ sdk: "fluid", runId: "fluid-0001" }),
  ], contract);
  assert.equal(result.watershed.validTrials, 2);
  assert.equal(result.watershed.invalidTrials, 1);
  assert.equal(result.watershed.passedTrials, 1);
  assert.equal(result.watershed.passRate, 0.5);
  assert.equal(result.watershed.groups.local.passRate, 1);
  assert.equal(result.watershed.groups.collaboration.passRate, 0.5);
  assert.equal(result.watershed.checks["collaboration.remote"].passRate, 0.5);
  assert.equal(result.fluid.passRate, 1);
});

test("absent valid trials have unavailable rates, not zero or success", () => {
  const result = summarize([
    report({ classification: "infrastructure" }),
  ], contract);
  assert.equal(result.watershed.validTrials, 0);
  assert.equal(result.watershed.invalidTrials, 1);
  assert.equal(result.watershed.passRate, null);
  assert.equal(result.watershed.groups.local.passRate, null);
  assert.equal(result.fluid.validTrials, 0);
  assert.equal(result.fluid.passRate, null);
});

test("rejects duplicate trial IDs rather than inflating success rates", () => {
  assert.throws(() => summarize([report(), report()], contract), /duplicate.*run/i);
});

test("summaries reject incomplete reports rather than quietly ignoring them", () => {
  assert.throws(() => summarize([report({ checks: [] })], contract), /missing/i);
});
