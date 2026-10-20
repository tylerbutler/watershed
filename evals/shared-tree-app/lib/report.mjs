import { requiredCheckIds, validateContract } from "./contract.mjs";

function record(value, keys, label) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new TypeError(`${label} must be an object`);
  }
  const unknown = Object.keys(value).filter(key => !keys.includes(key));
  if (unknown.length) throw new TypeError(`${label} has unknown fields: ${unknown.join(", ")}`);
}

export function validateReport(value, contract) {
  const expected = new Set(requiredCheckIds(contract));
  record(value, ["version", "runId", "sdk", "classification", "checks"], "Report");
  if (value.version !== 1) throw new TypeError("Unsupported report version");
  if (typeof value.runId !== "string" || value.runId.trim() === "") {
    throw new TypeError("Report runId must be a nonempty string");
  }
  if (!["watershed", "fluid"].includes(value.sdk)) throw new TypeError("Unknown report SDK");
  if (!["agent", "infrastructure"].includes(value.classification)) {
    throw new TypeError("Unknown report classification");
  }
  if (!Array.isArray(value.checks)) throw new TypeError("Report checks must be an array");
  const seen = new Set();
  for (const check of value.checks) {
    record(check, ["id", "passed", "durationMs", "evidence"], "Check result");
    if (!expected.has(check.id)) throw new TypeError(`Unknown check result: ${check.id}`);
    if (seen.has(check.id)) throw new TypeError(`Duplicate check result: ${check.id}`);
    if (typeof check.passed !== "boolean") {
      throw new TypeError(`Check ${check.id} passed must be boolean`);
    }
    if (typeof check.durationMs !== "number" || !Number.isFinite(check.durationMs) || check.durationMs < 0) {
      throw new TypeError(`Check ${check.id} durationMs must be a finite nonnegative number`);
    }
    if (typeof check.evidence !== "string" || check.evidence.trim() === "") {
      throw new TypeError(`Check ${check.id} requires nonempty evidence`);
    }
    seen.add(check.id);
  }
  const missing = [...expected].filter(id => !seen.has(id));
  if (missing.length) throw new TypeError(`Missing check results: ${missing.join(", ")}`);
  return value;
}

export function verdict(report, contract) {
  validateReport(report, contract);
  if (report.classification === "infrastructure") return "invalid";
  return report.checks.every(check => check.passed) ? "passed" : "failed";
}

export function summarize(reports, contract) {
  validateContract(contract);
  if (!Array.isArray(reports)) throw new TypeError("Reports must be an array");
  const seen = new Set();
  const validated = reports.map(report => {
    validateReport(report, contract);
    if (seen.has(report.runId)) throw new TypeError(`Duplicate run ID: ${report.runId}`);
    seen.add(report.runId);
    return report;
  });
  const groups = contract.groups.map(group => [
    group.id, contract.checks.filter(check => check.group === group.id).map(check => check.id),
  ]);
  return Object.fromEntries(["watershed", "fluid"].map(sdk => {
    const selected = validated.filter(report => report.sdk === sdk);
    const valid = selected.filter(report => report.classification === "agent");
    const outcomes = valid.map(report => new Map(report.checks.map(check => [check.id, check.passed])));
    const stats = ids => {
      const passedTrials = outcomes.filter(checks => ids.every(id => checks.get(id))).length;
      return { passedTrials, passRate: valid.length === 0 ? null : passedTrials / valid.length };
    };
    return [sdk, {
      validTrials: valid.length,
      invalidTrials: selected.length - valid.length,
      ...stats(contract.checks.map(check => check.id)),
      groups: Object.fromEntries(groups.map(([id, checks]) => [id, stats(checks)])),
      checks: Object.fromEntries(contract.checks.map(check => [check.id, stats([check.id])])),
    }];
  }));
}
