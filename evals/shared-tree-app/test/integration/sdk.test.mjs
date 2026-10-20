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
import { startServices } from "../../lib/services.mjs";
import { launchBrowser } from "../../lib/cdp.mjs";
import { runScenarios } from "../../graders/scenarios.mjs";

const exec = promisify(execFile);
const benchmark = fileURLToPath(new URL("../../", import.meta.url));
const source = process.env.SHARED_TREE_FLUID_SOURCE ??
  fileURLToPath(new URL("../../../../tools/shared-tree-oracle/.reference/FluidFramework", import.meta.url));
const revision = "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960";

for (const name of ["watershed", "fluid"]) {
  test(`${name} prepared SDK passes native grading without host layout, registry fallback, or SDK tests`, async () => {
    await mkdir(join(benchmark, ".work"), { recursive: true });
    const temporary = await mkdtemp(join(benchmark, `.work/local-${name}-sdk-`));
    let services;
    let browser;
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
      await exec("pnpm", ["install", "--frozen-lockfile"], { cwd: root, timeout: 300_000 });
      await exec("pnpm", ["check"], { cwd: root, timeout: 180_000 });
      await exec("pnpm", ["build"], { cwd: root, timeout: 180_000 });
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
      await cp(join(benchmark, "graders", name, "native.mjs"), join(root, "grade-native.mjs"));
      const entry = name === "fluid" ? "./src/index.tsx"
        : "./build/dev/javascript/incident_eval/incident_eval/shell.mjs";
      await writeFile(join(root, "grade-entry.mjs"),
        `export * from ${JSON.stringify(entry)};\nimport "./grade-native.mjs";\n`);
      await exec(process.execPath, ["--input-type=module", "-e", `
import { build } from "esbuild";
await build({ entryPoints: ["grade-entry.mjs"], bundle: true, format: "esm",
outfile: "dist/app.js", define: { "process.env.NODE_ENV": '"production"' } });
`], { cwd: root, timeout: 180_000 });
      services = await startServices({ sdk: name, root, runId: "local-sdk-validation" });
      browser = await launchBrowser();
      const checks = [];
      await runScenarios({ sdk: name, services, browser, record: check => checks.push(check) });
      const contract = JSON.parse(await readFile(join(benchmark, "contract.json"), "utf8"));
      assert.deepEqual(checks.map(check => check.id).sort(),
        contract.checks.filter(check => check.group !== "integrity").map(check => check.id).sort());
      assert.ok(checks.every(check => check.passed));
    } finally {
      if (browser) await browser.close();
      if (services) await services.close();
      await rm(temporary, { recursive: true, force: true });
    }
  });
}
