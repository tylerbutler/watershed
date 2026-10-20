import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { cp, mkdir, mkdtemp, readFile, readdir, rm, symlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import test from "node:test";
import { stringify } from "yaml";
import { buildImages } from "../../lib/images.mjs";
import { offlineSetupCommands, writeRoleCompose } from "../../lib/isolation.mjs";
import { prepare } from "../../prepare.mjs";
import { validateReport, verdict } from "../../lib/report.mjs";

const exec = promisify(execFile);
const benchmark = fileURLToPath(new URL("../../", import.meta.url));

for (const sdk of ["watershed", "fluid"]) {
test(`Vally mock task grades the native ${sdk} reference in a fresh isolated role and exports its report`, async () => {
  await mkdir(join(benchmark, ".work"), { recursive: true });
  const root = await mkdtemp(join(benchmark, ".work/vally-"));
  try {
    const source = sdk === "watershed" ? fileURLToPath(new URL("../../../../", import.meta.url))
      : fileURLToPath(new URL("../../../../tools/shared-tree-oracle/.reference/FluidFramework", import.meta.url));
    const revision = (await exec("git", ["rev-parse", "HEAD"], { cwd: source })).stdout.trim();
    const prepared = await prepare({ sdk, source, revision, out: join(root, "prepared") });
    const images = await buildImages({ prepared, out: join(root, "images") });
    const gradingOutput = join(root, "grade-output");
    const compose = join(root, "compose.yaml");
    await writeRoleCompose({ sdk, images, serviceImage: images.service.id,
      gradingOutput, out: compose });
    for (const name of ["model", "schema"]) await cp(
      join(benchmark, "validation/solutions", sdk, `${name}.${sdk === "watershed" ? "gleam" : "ts"}`),
      join(prepared.agentRoot, sdk === "watershed" ? "src/incident_eval" : "src",
        `${name}.${sdk === "watershed" ? "gleam" : "ts"}`));
    const spec = join(root, "eval.yaml");
    await writeFile(spec, stringify({
      name: "shared-tree-container-fixture", version: "1.0", type: "capability",
      defaults: { executor: "mock", model: "fixture-model", runs: 1, timeout: "2m" },
      agent_environment: {
        files: [{ src: prepared.agentRoot, dest: "." }],
        commands: [
          ...offlineSetupCommands(sdk),
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
        ],
      },
      stimuli: [{
        name: "incident-response-board", prompt: "No model call: preserve this synthetic candidate.",
        graders: [{ type: "run-command", name: "native-board", config: {
          command: "node", args: ["/opt/shared-tree/grading/graders/main.mjs", "--sdk", sdk,
            "--workspace", "/workspace", "--run-id", `fixture-${sdk}`, "--output", "/eval-results/report.json"],
          expected_exit_code: 0, stdout_contains: "SHARED_TREE_EVAL_ALL_REQUIRED_PASSED", timeout: "5m",
        } }],
      }], scoring: { threshold: 1 },
    }));
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
    await exec("pnpm", ["exec", "vally", "lint", "--eval-spec", spec], { cwd: benchmark, env, timeout: 30_000 });
    await exec("pnpm", ["exec", "vally", "eval", "--eval-spec", spec, "--backend", "docker",
      "--backend-args", `task-image=${images.task.id}`, "--backend-args", `grade-image=${images.grade.id}`,
      "--backend-args", `compose-file=${compose}`, "--workers", "1", "--max-retries", "0", "--require-pass",
      "--output-dir", join(root, "results")], { cwd: benchmark, env, timeout: 600_000, maxBuffer: 4 * 1024 * 1024 });
    const contract = JSON.parse(await readFile(join(benchmark, "contract.json"), "utf8"));
    const report = JSON.parse(await readFile(join(gradingOutput, "report.json"), "utf8"));
    validateReport(report, contract);
    assert.equal(verdict(report, contract), "passed");
    assert.ok((await readFile(join(gradingOutput, "report.json.build.log"), "utf8")).length > 0);
    const results = await readdir(join(root, "results"), { recursive: true, withFileTypes: true });
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
    for (const directory of ["grade-output", "results"]) {
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
