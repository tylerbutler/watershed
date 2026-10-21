import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import test from "node:test";
import { stringify } from "yaml";
import { benchmarkIdentity, buildSpec } from "../generate.mjs";

const options = sdk => ({
  sdk, prepared: { agentRoot: `/prepared/${sdk}/agent`, sdkManifest: { sdk } },
  model: "operator-model", reasoningEffort: "high", runId: `${sdk}-001`,
  limits: { agentDuration: "10m" },
});

test("matched specs share task, model, effort, and time limit without a token cap", () => {
  const specs = ["watershed", "fluid"].map(sdk => buildSpec(options(sdk)));
  assert.deepEqual(specs[0].defaults, specs[1].defaults);
  assert.equal(specs[0].defaults.runs, 1);
  assert.equal(specs[0].defaults.timeout, "660000ms");
  assert.deepEqual(specs[0].stimuli[0].constraints, { max_agent_duration: "10m" });
  assert.deepEqual(specs[0].stimuli[0].constraints, specs[1].stimuli[0].constraints);
  assert.equal(specs[0].stimuli[0].prompt, specs[1].stimuli[0].prompt);
  assert.match(benchmarkIdentity.taskSha256, /^[a-f0-9]{64}$/);
  assert.match(benchmarkIdentity.contractSha256, /^[a-f0-9]{64}$/);
  for (const spec of specs) {
    assert.equal(spec.grading_environment, undefined);
    assert.equal(spec.defaults.executor.config.provider.baseUrl, "http://provider-gateway:8080/v1");
    assert.ok(spec.stimuli[0].graders[0].config.args.includes("/eval-results/report.json"));
    assert.equal(JSON.stringify(spec).includes("max_tokens"), false);
  }
});

test("generation rejects missing operator settings, unsupported effort, and invalid limits", () => {
  for (const changed of [
    { model: "" }, { reasoningEffort: undefined }, { reasoningEffort: "automatic" },
    { limits: {} }, { limits: { agentDuration: "0s" } }, { limits: { agentDuration: "Infinity" } },
    { limits: { agentDuration: "10m", maxTokens: 50 } }, { runId: "../escape" },
    { sdk: "other" }, { prepared: { agentRoot: "/prepared", sdkManifest: { sdk: "fluid" } } },
  ]) assert.throws(() => buildSpec({ ...options("watershed"), ...changed }));
});

test("installed Vally lints generated specs using its real provider and duration fields", async () => {
  const root = await mkdtemp(join(tmpdir(), "shared-tree-spec-"));
  try {
    for (const sdk of ["watershed", "fluid"]) {
      const path = join(root, `${sdk}.yaml`);
      const config = options(sdk);
      config.prepared.agentRoot = root;
      await writeFile(path, stringify(buildSpec(config)));
      await promisify(execFile)("pnpm", ["exec", "vally", "lint", "--eval-spec", path],
        { cwd: new URL("../", import.meta.url), timeout: 30_000 });
    }
  } finally { await rm(root, { recursive: true, force: true }); }
});
