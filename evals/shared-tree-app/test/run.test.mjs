import assert from "node:assert/strict";
import { access, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { buildSpec } from "../generate.mjs";
import { runPair, runVallyTrial, trialOrder } from "../run.mjs";
import { verdict } from "../lib/report.mjs";
import { wait } from "../lib/conditions.mjs";

const contract = JSON.parse(await readFile(new URL("../contract.json", import.meta.url), "utf8"));
const fixture = `
import {mkdir,readFile,writeFile} from "node:fs/promises";
import {join} from "node:path";
if(process.argv[2] === "lint") process.exit(process.env.FIXTURE_MODE === "lint-error" ? 2 : 0);
const root=process.env.FIXTURE_ROOT, mode=process.env.FIXTURE_MODE;
if(mode === "interrupt") {
  await writeFile(join(root,"eval-started"),"ready");
  setInterval(()=>{},1000);
  await new Promise(()=>{});
}
const report=JSON.parse(await readFile(join(root,"fixture-report.json"),"utf8"));
if(mode === "failed") report.checks[0].passed=false;
if(mode !== "missing-report") await writeFile(join(root,"native/report.json"),JSON.stringify(report));
await writeFile(join(root,"native/report.json.build.log"),"trusted compiler diagnostics");
await mkdir(join(root,"vally/fixture"),{recursive:true});
const passed=mode !== "failed";
const result={type:"trial-result",status:"success",model:mode === "wrong-model" ? "other" : "operator-model",
  trajectory:{metadata:{model:"operator-model"},metrics:{wallTimeMs:250,toolCallCount:2,tokenUsage:{totalTokens:300}}},
  gradeResult:{passed,details:[{configuredName:"native-board",passed,metadata:{
    stdout:passed && mode !== "missing-marker" ? "SHARED_TREE_EVAL_ALL_REQUIRED_PASSED" : "",stderr:""
  }}]}};
if(mode === "bad-metrics") result.trajectory.metrics.wallTimeMs="not-a-duration";
if(mode === "missing-metrics") delete result.trajectory.metrics;
if(mode === "unobserved-usage") result.trajectory.metrics.tokenUsage={inputTokens:0,outputTokens:0,totalTokens:0,callCount:0,byModel:{}};
await writeFile(join(root,"vally/fixture/results.jsonl"),mode === "malformed" ? "{}" : JSON.stringify(result));
const spans=["task.start","task.down","grade.start","grade.down"].map((phase,index)=>({
  attributes:{"vally.docker.phase":phase,"vally.docker.project":index<2?"task-project":"grade-project",
    "vally.docker.result":mode === "cleanup-error" && phase === "grade.down" ? "error" : "success"},
  startTime:[index,0],endTime:[index+1,0]}));
await writeFile(join(root,"vally/fixture/otel-spans.jsonl"),spans.map(span=>JSON.stringify(span)).join("\\n"));
process.exit(mode === "bad-exit" || mode === "failed" ? 1 : 0);
`;

async function runFixture(mode) {
  const root = await mkdtemp(join(tmpdir(), "shared-tree-run-"));
  try {
    await mkdir(join(root, "native"));
    const cli = join(root, "fake-vally.mjs");
    await writeFile(cli, fixture);
    await mkdir(join(root, "bin"));
    await writeFile(join(root, "bin/docker"), `#!${process.execPath}
if(process.env.FIXTURE_MODE === "retained-volume" && process.argv[2] === "volume") {
  if(process.argv[3] === "ls") console.log("recovery-workspace");
  else if(process.argv[3] === "inspect") console.log(JSON.stringify([{Labels:{"com.microsoft.vally.run":"watershed-001"}}]));
  else process.exit(99);
}
`, { mode: 0o700 });
    const report = { version: 1, runId: "watershed-001", sdk: "watershed", classification: "agent",
      checks: contract.checks.map(({ id }) => ({ id, passed: true, durationMs: 1, evidence: "Native check passed" })) };
    await writeFile(join(root, "fixture-report.json"), JSON.stringify(report));
    const spec = buildSpec({ sdk: "watershed", prepared: { agentRoot: root, sdkManifest: { sdk: "watershed" } },
      model: "operator-model", reasoningEffort: "high", limits: { agentDuration: "1m" }, runId: report.runId });
    spec.defaults.executor = "mock";
    const controller = new AbortController();
    if (mode === "already-aborted") controller.abort();
    const pending = runVallyTrial({
      spec, root, cli, images: { task: { id: "task-image" }, grade: { id: "grade-image" } },
      composeFile: join(root, "compose.yaml"),
      signal: controller.signal,
      env: { ...process.env, FIXTURE_ROOT: root, FIXTURE_MODE: mode, PATH: `${join(root, "bin")}:${process.env.PATH}` },
    });
    if (mode === "interrupt") {
      await wait("fake trial running", async () => {
        try { return await readFile(join(root, "eval-started"), "utf8"); }
        catch (error) { if (error.code === "ENOENT") return false; throw error; }
      }, Boolean);
      controller.abort();
    }
    return await pending;
  } finally { await rm(root, { recursive: true, force: true }); }
}

test("runner preserves passing native reports and extracts only observed Vally metrics", async () => {
  const trial = await runFixture("passed");
  assert.equal(verdict(trial.report, contract), "passed");
  assert.equal(trial.metrics.agentDurationMs, 250);
  assert.equal(trial.metrics.toolCalls, 2);
  assert.equal(trial.metrics.tokens.totalTokens, 300);
  assert.equal(trial.metrics.cost, null);
  assert.match(trial.metrics.costUnavailable, /provider|identity/i);
});

test("candidate failure is an agent outcome despite Vally's require-pass exit code", async () => {
  assert.equal(verdict((await runFixture("failed")).report, contract), "failed");
});

test("missing evidence, invalid formats, mismatched model, and inconsistent exits are infrastructure-invalid", async () => {
  for (const mode of ["lint-error", "missing-report", "missing-marker", "malformed", "wrong-model", "bad-exit",
    "cleanup-error", "bad-metrics"]) {
    const trial = await runFixture(mode);
    assert.equal(verdict(trial.report, contract), "invalid", mode);
    assert.ok(trial.report.checks.every(check => check.evidence.length > 0));
  }
});

test("trial order alternates API order without retries, replacements, or token budgets", () => {
  assert.deepEqual(trialOrder(3), [
    { sdk: "watershed", trial: 1 }, { sdk: "fluid", trial: 1 },
    { sdk: "fluid", trial: 2 }, { sdk: "watershed", trial: 2 },
    { sdk: "watershed", trial: 3 }, { sdk: "fluid", trial: 3 },
  ]);
  for (const value of [0, -1, 1.2, undefined]) assert.throws(() => trialOrder(value));
});

test("operator validation and explicit paid authorization happen before output creation or subprocesses", async () => {
  const parent = await mkdtemp(join(tmpdir(), "shared-tree-authorization-"));
  try {
    const out = join(parent, "results");
    const options = {
      sources: { watershed: "/operator/watershed", fluid: "/operator/fluid" },
      revisions: { watershed: "a".repeat(40), fluid: "b".repeat(40) },
      model: "operator-model", reasoningEffort: "high", runs: 1,
      limits: { agentDuration: "10m" }, out,
    };
    await assert.rejects(runPair(options), /authorize-paid/);
    await assert.rejects(runPair({ ...options, limits: { agentDuration: "10m", maxTokens: 100 } }), /agentDuration only/);
    await assert.rejects(runPair({ ...options, authorizePaid: true, env: {
      SHARED_TREE_PROVIDER_URL: "https://provider.example/v1",
    } }), /environment API key/);
    await assert.rejects(access(out), { code: "ENOENT" });
  } finally { await rm(parent, { recursive: true, force: true }); }
});

test("an interrupted trial is infrastructure-invalid after owned subprocess cleanup", async () => {
  const result = await runFixture("interrupt");
  assert.equal(verdict(result.report, contract), "invalid");
  assert.match(result.controllerError, /abort|interrupt/i);
  assert.deepEqual(result.cleanup.removed, []);
});

test("an already cancelled trial does not execute the candidate", async () => {
  const result = await runFixture("already-aborted");
  assert.equal(verdict(result.report, contract), "invalid");
  assert.equal(result.metrics, null);
});

test("unexported recovery work is retained and makes an otherwise passing trial invalid", async () => {
  const result = await runFixture("retained-volume");
  assert.equal(verdict(result.report, contract), "invalid");
  assert.deepEqual(result.cleanup.preserved, [{ kind: "volume", id: "recovery-workspace" }]);
  assert.match(result.controllerError, /preserv|recovery/i);
});

test("missing usage metrics stay unavailable with explicit reasons instead of invented zeros", async () => {
  const result = await runFixture("missing-metrics");
  assert.equal(verdict(result.report, contract), "passed");
  assert.equal(result.metrics.agentDurationMs, null);
  assert.equal(result.metrics.tokens, null);
  assert.equal(result.metrics.toolCalls, null);
  assert.equal(result.metrics.unavailable.length, 3);
});

test("Vally's empty token counters do not claim a model consumed zero tokens", async () => {
  const result = await runFixture("unobserved-usage");
  assert.equal(result.metrics.tokens, null);
  assert.ok(result.metrics.unavailable.some(reason => /no token.usage observations/i.test(reason)));
});
