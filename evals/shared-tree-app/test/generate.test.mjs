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

test("transfer specs select their own task, grading track, and contract without changing core prompts", () => {
  const core = buildSpec(options("watershed"));
  const advanced = ["watershed", "fluid"].map(sdk =>
    buildSpec({ ...options(sdk), track: "transfers",
      prepared: { ...options(sdk).prepared, track: "transfers", sdkManifest: { sdk, track: "transfers" } } }));
  assert.equal(core.tags.track, "core");
  assert.equal(advanced[0].tags.track, "transfers");
  assert.equal(advanced[0].stimuli[0].prompt, advanced[1].stimuli[0].prompt);
  assert.notEqual(advanced[0].tags.taskSha256, core.tags.taskSha256);
  assert.notEqual(advanced[0].tags.contractSha256, core.tags.contractSha256);
  assert.match(advanced[0].stimuli[0].prompt, /transfer-step/);
  assert.doesNotMatch(core.stimuli[0].prompt, /transfer-step/);
  assert.throws(() => buildSpec({ ...options("watershed"), track: "../escape" }), /track/i);
  assert.throws(() => buildSpec({ ...options("watershed"), track: "transfers" }), /track mismatch/i);
});

test("generation rejects missing operator settings, unsupported effort, and invalid limits", () => {
  for (const changed of [
    { model: "" }, { reasoningEffort: undefined }, { reasoningEffort: "automatic" },
    { limits: {} }, { limits: { agentDuration: "0s" } }, { limits: { agentDuration: "Infinity" } },
    { limits: { agentDuration: "10m", maxTokens: 50 } }, { runId: "../escape" },
    { sdk: "other" }, { auth: "automatic" },
    { prepared: { agentRoot: "/prepared", sdkManifest: { sdk: "fluid" } } },
  ]) assert.throws(() => buildSpec({ ...options("watershed"), ...changed }));
});

test("Copilot specs select the account model protocol without exposing account authentication", () => {
  for (const wireApi of ["completions", "responses", "messages"]) {
    const spec = buildSpec({ ...options("watershed"), auth: "copilot", wireApi });
    const provider = spec.defaults.executor.config.provider;
    assert.equal(provider.type, wireApi === "messages" ? "anthropic" : "openai");
    assert.equal(provider.baseUrl, "http://provider-gateway:8080");
    assert.equal(provider.wireApi, wireApi === "messages" ? undefined : wireApi);
    assert.deepEqual(spec.agent_environment.env, {
      COPILOT_OFFLINE: "true", SHARED_TREE_GATEWAY_CLIENT_KEY: "gateway-client-placeholder",
    });
  }
});

test("installed Vally lints generated specs using its real provider and duration fields", async () => {
  const root = await mkdtemp(join(tmpdir(), "shared-tree-spec-"));
  try {
    for (const [sdk, auth, wireApi, track = "core"] of [
      ["watershed", "provider", "completions"], ["fluid", "provider", "completions"],
      ["watershed", "copilot", "completions"], ["watershed", "copilot", "responses"],
      ["watershed", "copilot", "messages"],
      ["watershed", "copilot", "responses", "transfers"],
    ]) {
      const path = join(root, `${sdk}-${auth}-${wireApi}.yaml`);
      const config = options(sdk);
      config.prepared.agentRoot = root;
      config.prepared.track = track;
      config.prepared.sdkManifest.track = track;
      await writeFile(path, stringify(buildSpec({ ...config, auth, wireApi, track })));
      await promisify(execFile)("pnpm", ["exec", "vally", "lint", "--eval-spec", path],
        { cwd: new URL("../", import.meta.url), timeout: 30_000 });
    }
  } finally { await rm(root, { recursive: true, force: true }); }
});
