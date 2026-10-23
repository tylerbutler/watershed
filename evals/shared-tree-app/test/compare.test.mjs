import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { compare } from "../compare.mjs";
import { benchmarkIdentity } from "../generate.mjs";

const contract = JSON.parse(await readFile(new URL("../contract.json", import.meta.url), "utf8"));
function trial(sdk, changes = {}) {
  const runId = `${sdk}-001`;
  const runtime = () => ({
    architecture: "arm64", coreVersion: "0.19.0", cliVersion: "0.19.0", uid: 1000,
    toolchain: { node: "v24.21.0", pnpm: "12.13.0", gleam: "gleam 1.18.1", chromium: "fixture Chromium" },
  });
  return {
    manifest: { version: 1, runId, sdk, ...benchmarkIdentity, model: "operator-model",
      reasoningEffort: "high", limits: { agentDuration: "10m" }, executor: "copilot-sdk",
      providerUrl: "https://provider.example/v1", revision: "a".repeat(40),
      evalSha256: "c".repeat(64), starterSha256: (sdk === "watershed" ? "d" : "e").repeat(64),
      images: { task: runtime(), grade: runtime(), vallyPatchSha256: "f".repeat(64) }, ...changes },
    report: { version: 1, runId, sdk, classification: "agent", checks: contract.checks.map(({ id }) =>
      ({ id, passed: true, durationMs: 1, evidence: "Native assertion passed" })) },
    metrics: { agentDurationMs: 1000, toolCalls: 3, tokens: null, cost: null },
  };
}

test("comparison rejects mismatched model, effort, task, provider, and working limit", () => {
  for (const changed of [
    { model: "different" }, { reasoningEffort: "low" }, { taskSha256: "b".repeat(64) },
    { providerUrl: "https://different.example/v1" }, { limits: { agentDuration: "11m" } },
    { evalSha256: "b".repeat(64) },
  ]) assert.throws(() => compare([trial("watershed"), trial("fluid", changed)]), /mismatch/i);
});

test("comparison rejects mismatched observed architecture and pinned runtime versions", () => {
  for (const changes of [{ architecture: "amd64" }, { cliVersion: "0.20.0" }]) {
    const different = trial("fluid");
    Object.assign(different.manifest.images.task, changes);
    assert.throws(() => compare([trial("watershed"), different]), /mismatch/i);
  }
});

test("comparison separates Copilot-account trials from provider trials and rejects unknown authentication", () => {
  const providerUrl = "https://api.githubcopilot.com/";
  assert.throws(() => compare([
    trial("watershed", { providerUrl, authMode: "copilot" }),
    trial("fluid", { providerUrl, authMode: "provider" }),
  ]), /mismatch/i);
  assert.throws(() => compare([trial("watershed", { authMode: "automatic" })]), /auth/i);
  assert.throws(() => compare([trial("watershed", { authMode: null })]), /auth/i);
  assert.throws(() => compare([trial("watershed", { authMode: "copilot" })]), /Copilot.*provider/i);
  assert.throws(() => compare([
    trial("watershed", { providerUrl, authMode: "copilot", wireApi: "responses" }),
    trial("fluid", { providerUrl, authMode: "copilot", wireApi: "completions" }),
  ]), /mismatch/i);
  const result = compare(["watershed", "fluid"].map(sdk => trial(sdk, { providerUrl, authMode: "copilot" })));
  assert.equal(result.watershed.passRate, 1);
});

test("invalid trials remain visible outside agent denominators and metrics stay unmodified", () => {
  const invalid = trial("watershed");
  invalid.report.classification = "infrastructure";
  const summary = compare([invalid, trial("fluid")]);
  assert.equal(summary.watershed.invalidTrials, 1);
  assert.equal(summary.watershed.validTrials, 0);
  assert.equal(summary.watershed.passRate, null);
  assert.equal(summary.fluid.passRate, 1);
  assert.equal(summary.fluid.trials[0].metrics.cost, null);
  assert.equal(summary.fluid.trials[0].metrics.tokens, null);
});

test("comparison rejects missing checks, altered identities, duplicate trials, and mixed revisions within one SDK", () => {
  const broken = trial("watershed");
  broken.report.checks.pop();
  assert.throws(() => compare([broken, trial("fluid")]), /missing/i);
  const mismatched = trial("watershed");
  mismatched.report.runId = "different";
  assert.throws(() => compare([mismatched]), /identity/i);
  assert.throws(() => compare([trial("watershed"), trial("watershed")]), /duplicate/i);
  const another = trial("watershed", { runId: "watershed-002", revision: "b".repeat(40) });
  another.report.runId = another.manifest.runId;
  assert.throws(() => compare([trial("watershed"), another]), /revision/i);
});
