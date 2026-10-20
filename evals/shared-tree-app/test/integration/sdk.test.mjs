import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { cp, mkdir, mkdtemp, readFile, readdir, rm, symlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { promisify } from "node:util";
import test from "node:test";
import { parse } from "yaml";
import { prepare } from "../../prepare.mjs";
import { verifyIntegrity } from "../../lib/staging.mjs";
import { validateReport, verdict } from "../../lib/report.mjs";

const exec = promisify(execFile);
const benchmark = fileURLToPath(new URL("../../", import.meta.url));
const source = process.env.SHARED_TREE_FLUID_SOURCE ??
  fileURLToPath(new URL("../../../../tools/shared-tree-oracle/.reference/FluidFramework", import.meta.url));
const revision = "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960";

for (const name of ["watershed", "fluid"]) {
  test(`${name} prepared SDK passes native grading without host layout, registry fallback, or SDK tests`, async () => {
    await mkdir(join(benchmark, ".work"), { recursive: true });
    const temporary = await mkdtemp(join(benchmark, `.work/local-${name}-sdk-`));
    try {
      const selectedSource = name === "fluid" ? source : fileURLToPath(new URL("../../../../", import.meta.url));
      const selectedRevision = name === "fluid" ? revision
        : (await exec("git", ["rev-parse", "HEAD"], { cwd: selectedSource })).stdout.trim();
      let prepareWorkspace = prepare;
      if (name === "fluid") {
        const standalone = join(temporary, "standalone");
        await mkdir(standalone);
        for (const path of ["prepare.mjs", "lib", "graders", "docker", "fluid", "task.md", "contract.json",
          "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml"]) {
          await cp(join(benchmark, path), join(standalone, path), { recursive: true, filter: path =>
            !["node_modules", "dist"].some(part => path.split("/").includes(part)) });
        }
        await symlink(join(benchmark, "node_modules"), join(standalone, "node_modules"));
        prepareWorkspace = (await import(pathToFileURL(join(standalone, "prepare.mjs")).href)).prepare;
      }
      const prepared = await prepareWorkspace({ sdk: name, source: selectedSource, revision: selectedRevision,
        out: join(temporary, "prepared") });
      const root = prepared.agentRoot;
      const sdk = prepared.sdkManifest;
      const extension = name === "fluid" ? "ts" : "gleam";
      for (const module of ["model", "schema"]) await cp(
        join(benchmark, "validation/solutions", name, `${module}.${extension}`),
        join(root, name === "fluid" ? "src" : "src/incident_eval", `${module}.${extension}`));
      if (name === "fluid") {
        const lock = parse(await readFile(join(root, "pnpm-lock.yaml"), "utf8"));
        for (const pkg of sdk.packages) {
          assert.equal(lock.packages[`${pkg.name}@${pkg.version}`], undefined,
            `${pkg.name} must come from the selected local build, not the registry`);
          assert.ok(Object.keys(lock.packages).some(key =>
            key.startsWith(`${pkg.name}@file:${sdk.root}/${pkg.stagedPath}`)), `Missing local ${pkg.name}`);
        }
      }
      assert.equal((await verifyIntegrity({ workspace: root, manifest: prepared.integrityManifest })).passed, true);
      const files = await readdir(join(root, "sdk"), { recursive: true });
      assert.equal(files.some(path => /(^|\/)(test|tests|examples|validation|\.git)(\/|$)/.test(path)), false);
      assert.equal(sdk.build.mode, name === "fluid" ? "esm" : "source");
      assert.equal(sdk.build.revision, selectedRevision);
      const baseline = join(prepared.gradingRoot, "workspace");
      await exec("pnpm", ["install", "--frozen-lockfile"], { cwd: baseline, timeout: 300_000 });
      await exec("pnpm", ["check"], { cwd: baseline, timeout: 180_000 });
      await exec("pnpm", ["build"], { cwd: baseline, timeout: 180_000 });
      await mkdir(join(root, "dist"));
      await writeFile(join(root, "dist/app.js"), 'throw new Error("Untrusted generated output must not run");');
      const output = join(temporary, "passed.json");
      const cli = join(prepared.gradingRoot, "graders/main.mjs");
      const args = [cli, "--sdk", name, "--workspace", root, "--run-id", "local-sdk-validation",
        "--output", output];
      const passed = await exec(process.execPath, args, { timeout: 300_000, maxBuffer: 4 * 1024 * 1024 });
      assert.match(passed.stdout, /^SHARED_TREE_EVAL_ALL_REQUIRED_PASSED\n$/);
      const contract = JSON.parse(await readFile(join(benchmark, "contract.json"), "utf8"));
      const report = JSON.parse(await readFile(output, "utf8"));
      validateReport(report, contract);
      assert.equal(verdict(report, contract), "passed");
      const failedOutput = join(temporary, "failed.json");
      await writeFile(join(root, name === "fluid" ? "src/model.ts" : "src/incident_eval/model.gleam"),
        name === "fluid" ? "export function invalid(" : "pub fn invalid(");
      await assert.rejects(exec(process.execPath, [
        cli, "--sdk", name, "--workspace", root, "--run-id", "invalid-candidate", "--output", failedOutput,
      ], { timeout: 300_000, maxBuffer: 4 * 1024 * 1024 }), error => {
        assert.equal(error.code, 1);
        assert.equal(error.stdout.includes("SHARED_TREE_EVAL_ALL_REQUIRED_PASSED"), false);
        return true;
      });
      const failed = JSON.parse(await readFile(failedOutput, "utf8"));
      validateReport(failed, contract);
      assert.equal(failed.classification, "agent");
      assert.equal(failed.checks.find(check => check.id === "integrity.build").passed, false);
      assert.equal(verdict(failed, contract), "failed");
    } finally {
      await rm(temporary, { recursive: true, force: true });
    }
  });
}
