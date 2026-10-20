import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { cp, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import test from "node:test";
import { parse, stringify } from "yaml";
import { materializeSdk } from "../../lib/sdk-build.mjs";
import { startServices } from "../../lib/services.mjs";
import { launchBrowser } from "../../lib/cdp.mjs";
import { runScenarios } from "../../graders/scenarios.mjs";

const exec = promisify(execFile);
const benchmark = fileURLToPath(new URL("../../", import.meta.url));
const source = process.env.SHARED_TREE_FLUID_SOURCE ??
  fileURLToPath(new URL("../../../../tools/shared-tree-oracle/.reference/FluidFramework", import.meta.url));
const revision = "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960";

test("actual local Fluid source builds portable ESM packages without registry SDK fallback or SDK tests", async () => {
  await mkdir(join(benchmark, ".work"), { recursive: true });
  const root = await mkdtemp(join(benchmark, ".work/local-fluid-sdk-"));
  let services;
  let browser;
  try {
    await cp(join(benchmark, "fluid"), root, { recursive: true, filter: path =>
      !["node_modules", "dist"].some(part => relative(join(benchmark, "fluid"), path).split("/").includes(part)) });
    const sdk = await materializeSdk({ sdk: "fluid", source, revision, out: join(root, "sdk") });
    const manifest = JSON.parse(await readFile(join(root, "package.json"), "utf8"));
    const config = parse(await readFile(join(root, "pnpm-workspace.yaml"), "utf8"));
    config.overrides = {};
    const local = new Map(sdk.packages.map(pkg => [pkg.name, `file:./sdk/${pkg.stagedPath}`]));
    for (const group of ["dependencies", "devDependencies"]) {
      for (const name of Object.keys(manifest[group])) {
        if (local.has(name)) manifest[group][name] = local.get(name);
      }
    }
    for (const pkg of sdk.packages) {
      for (const dependency of pkg.workspaceDependencies) {
        config.overrides[`${pkg.name}@${pkg.version}>${dependency}`] = local.get(dependency);
      }
    }
    await writeFile(join(root, "package.json"), JSON.stringify(manifest, null, 2));
    await writeFile(join(root, "pnpm-workspace.yaml"), stringify(config));
    for (const name of ["model", "schema"]) await cp(
      join(benchmark, "validation/solutions/fluid", `${name}.ts`), join(root, "src", `${name}.ts`));
    await exec("pnpm", ["install", "--no-frozen-lockfile"], { cwd: root, timeout: 300_000 });
    await exec("pnpm", ["check"], { cwd: root, timeout: 180_000 });
    await exec("pnpm", ["build"], { cwd: root, timeout: 180_000 });
    const lock = parse(await readFile(join(root, "pnpm-lock.yaml"), "utf8"));
    for (const pkg of sdk.packages) {
      assert.equal(lock.packages[`${pkg.name}@${pkg.version}`], undefined,
        `${pkg.name} must come from the selected local build, not the registry`);
      assert.ok(Object.keys(lock.packages).some(key =>
        key.startsWith(`${pkg.name}@file:sdk/${pkg.stagedPath}`)), `Missing local ${pkg.name}`);
    }
    const files = await readdir(join(root, "sdk"), { recursive: true });
    assert.equal(files.some(path => /(^|\/)(test|tests|examples|validation|\.git)(\/|$)/.test(path)), false);
    assert.equal(sdk.build.mode, "esm");
    assert.equal(sdk.build.revision, revision);
    await cp(join(benchmark, "graders/fluid/native.mjs"), join(root, "grade-native.mjs"));
    await writeFile(join(root, "grade-entry.mjs"),
      'export * from "./src/index.tsx";\nimport "./grade-native.mjs";\n');
    await exec(process.execPath, ["--input-type=module", "-e", `
import { build } from "esbuild";
await build({ entryPoints: ["grade-entry.mjs"], bundle: true, format: "esm",
outfile: "dist/app.js", define: { "process.env.NODE_ENV": '"production"' } });
`], { cwd: root, timeout: 180_000 });
    services = await startServices({ sdk: "fluid", root, runId: "local-sdk-validation" });
    browser = await launchBrowser();
    const checks = [];
    await runScenarios({ sdk: "fluid", services, browser, record: check => checks.push(check) });
    const contract = JSON.parse(await readFile(join(benchmark, "contract.json"), "utf8"));
    assert.deepEqual(checks.map(check => check.id).sort(),
      contract.checks.filter(check => check.group !== "integrity").map(check => check.id).sort());
    assert.ok(checks.every(check => check.passed));
  } finally {
    if (browser) await browser.close();
    if (services) await services.close();
    await rm(root, { recursive: true, force: true });
  }
});
