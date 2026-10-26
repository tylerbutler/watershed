import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { cp, mkdir, mkdtemp, readFile, readdir, rm, symlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { randomUUID } from "node:crypto";
import test from "node:test";
import { getBenchmark, benchmarkProvenance, buildSpec } from "../../generate.mjs";
import { compare } from "../../compare.mjs";
import { buildImages } from "../../lib/images.mjs";
import { writeRoleCompose } from "../../lib/isolation.mjs";
import { prepare } from "../../prepare.mjs";
import { runVallyTrial } from "../../run.mjs";
import { validateReport, verdict } from "../../lib/report.mjs";

const exec = promisify(execFile);
const benchmark = fileURLToPath(new URL("../../", import.meta.url));
const track = process.env.SHARED_TREE_TEST_TRACK ?? "core";
const { identity: benchmarkIdentity, contract } = getBenchmark(track);
const trials = [];

for (const sdk of ["watershed", "fluid"]) {
test(`Vally mock task grades the native ${sdk}/${track} reference in a fresh isolated role and exports its report`, async () => {
  await mkdir(join(benchmark, ".work"), { recursive: true });
  const root = await mkdtemp(join(benchmark, ".work/vally-"));
  try {
    const source = sdk === "watershed" ? fileURLToPath(new URL("../../../../", import.meta.url))
      : fileURLToPath(new URL("../../../../tools/shared-tree-oracle/.reference/FluidFramework", import.meta.url));
    const revision = (await exec("git", ["rev-parse", "HEAD"], { cwd: source })).stdout.trim();
    const prepared = await prepare({ sdk, source, revision, out: join(root, "prepared"), track });
    const images = await buildImages({ prepared, out: join(root, "images") });
    const gradingOutput = join(root, "native");
    const compose = join(root, "compose.yaml");
    const runId = `fixture-${sdk}-${randomUUID()}`;
    await writeRoleCompose({ sdk, images, serviceImage: images.service.id,
      gradingOutput, out: compose, runId });
    for (const name of ["model", "schema"]) await cp(
      join(benchmark, "validation/solutions", ...(track === "core" ? [] : [track]),
        sdk, `${name}.${sdk === "watershed" ? "gleam" : "ts"}`),
      join(prepared.agentRoot, sdk === "watershed" ? "src/incident_eval" : "src",
        `${name}.${sdk === "watershed" ? "gleam" : "ts"}`));
    const spec = buildSpec({ sdk, prepared, model: "fixture-model", reasoningEffort: "high",
      limits: { agentDuration: "2m" }, runId, track });
    spec.defaults.executor = "mock";
    spec.agent_environment.commands.push(
          `node --input-type=module -e ${JSON.stringify(`
import assert from "node:assert/strict";
import { access } from "node:fs/promises";
for (const path of ${JSON.stringify([source, prepared.gradingRoot, gradingOutput,
  "/opt/shared-tree/grading", "/opt/shared-tree/validation", "/eval-results",
  "/var/run/docker.sock", "/run/podman/podman.sock"])}) {
  await assert.rejects(access(path), { code: "ENOENT" });
}
assert.equal(process.env.SHARED_TREE_PROVIDER_API_KEY, undefined);
assert.equal(process.getuid(), 1000);
assert.ok((await fetch("http://sdk-service:3000", { signal: AbortSignal.timeout(3000) })).status < 500);
assert.ok((await fetch("http://provider-gateway:8080/health", { signal: AbortSignal.timeout(3000) })).ok);
`.replaceAll("\n", " "))}`,
          "! curl --fail --connect-timeout 3 --max-time 5 https://github.com",
    );
    const config = join(root, "docker-client");
    await mkdir(config);
    const composePath = (await exec("sh", ["-c", "command -v docker-compose"])).stdout.trim();
    await mkdir(join(config, "cli-plugins"));
    await symlink(composePath, join(config, "cli-plugins/docker-compose"));
    await writeFile(join(config, "config.json"), "{}\n");
    const env = {
      ...process.env, DOCKER_CONFIG: config,
      SHARED_TREE_PROVIDER_URL: "https://fixture.invalid/v1",
      SHARED_TREE_PROVIDER_API_KEY: "harmless-compose-credential-canary",
      SHARED_TREE_PROVIDER_MODEL: "fixture-model",
    };
    const trial = await runVallyTrial({ spec, images, composeFile: compose, root, env });
    assert.equal(trial.controllerError, null);
    const report = JSON.parse(await readFile(join(gradingOutput, "report.json"), "utf8"));
    validateReport(report, contract);
    assert.equal(verdict(report, contract), "passed");
    assert.deepEqual(trial.report, report);
    assert.equal(typeof trial.metrics.agentDurationMs, "number");
    assert.equal(trial.metrics.cost, null);
    trials.push({
      ...trial,
      manifest: {
        version: 1, sdk, runId, revision, track, ...benchmarkIdentity, ...await benchmarkProvenance({ sdk, track }),
        model: "fixture-model", reasoningEffort: "high", limits: { agentDuration: "2m" },
        executor: "mock", providerUrl: env.SHARED_TREE_PROVIDER_URL, images,
      },
    });
    assert.ok((await readFile(join(gradingOutput, "report.json.build.log"), "utf8")).length > 0);
    const results = await readdir(join(root, "vally"), { recursive: true, withFileTypes: true });
    for (const file of results.filter(file => file.isFile())) {
      const content = await readFile(join(file.parentPath, file.name), "utf8");
      assert.equal(content.includes(env.SHARED_TREE_PROVIDER_API_KEY), false, `Credential leaked to ${file.name}`);
    }
    const traces = results.find(file => file.name === "otel-spans.jsonl");
    assert.ok(traces);
    const spans = (await readFile(join(traces.parentPath, traces.name), "utf8")).trim()
      .split("\n").map(line => JSON.parse(line));
    const phase = name => spans.find(span => span.attributes?.["vally.docker.phase"] === name);
    assert.notEqual(phase("task.start").attributes["vally.docker.project"],
      phase("grade.start").attributes["vally.docker.project"]);
    assert.equal(phase("task.down").attributes["vally.docker.result"], "success");
    assert.equal(phase("grade.down").attributes["vally.docker.result"], "success");
    const milliseconds = value => value[0] * 1000 + value[1] / 1_000_000;
    assert.ok(milliseconds(phase("task.down").endTime) <= milliseconds(phase("grade.start").startTime));
  } catch (error) {
    const artifacts = [];
    for (const directory of ["native", "vally"]) {
      let files;
      try { files = await readdir(join(root, directory), { recursive: true }); }
      catch (missing) { if (missing.code === "ENOENT") continue; throw missing; }
      for (const file of files.filter(file => /(?:results\.jsonl|report\.json|build\.log|compose\.log)$/.test(file))) {
        artifacts.push(`${directory}/${file}:\n${(await readFile(join(root, directory, file), "utf8")).slice(-30_000)}`);
      }
    }
    throw new Error(`${error.message}\n${artifacts.join("\n")}`, { cause: error });
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
}

test("the actual matched mock records produce one valid passing observation per SDK", () => {
  assert.equal(trials.length, 2);
  const summary = compare(trials);
  for (const sdk of ["watershed", "fluid"]) {
    assert.equal(summary[sdk].validTrials, 1);
    assert.equal(summary[sdk].invalidTrials, 0);
    assert.equal(summary[sdk].passRate, 1);
    assert.equal(summary[sdk].trials[0].metrics.cost, null);
  }
});
