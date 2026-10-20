import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdir, mkdtemp, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { promisify } from "node:util";
import test from "node:test";
import { resolveSdk } from "../lib/sdk.mjs";

const exec = promisify(execFile);

async function source(t, files) {
  const root = await mkdtemp(join(tmpdir(), "incident-sdk-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  for (const [path, content] of Object.entries(files)) {
    await mkdir(dirname(join(root, path)), { recursive: true });
    await writeFile(join(root, path), content);
  }
  await exec("git", ["init", "--quiet"], { cwd: root });
  await exec("git", ["add", "."], { cwd: root });
  await exec("git", ["-c", "user.name=Eval fixture", "-c", "user.email=eval@example.invalid",
    "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "SDK fixture"], { cwd: root });
  const revision = (await exec("git", ["rev-parse", "HEAD"], { cwd: root })).stdout.trim();
  return { root, revision };
}

const pkg = (name, extra = {}) => JSON.stringify({ name, version: "3.1.0", ...extra });
const fluidFiles = {
  "package.json": '{"private":true,"packageManager":"pnpm@11.15.1"}',
  "pnpm-lock.yaml": "lockfileVersion: '9.0'\n",
  "pnpm-workspace.yaml": "packages:\n  - packages/**\n  - azure/packages/*\n",
  "packages/framework/package.json": pkg("fluid-framework", {
    dependencies: { "@fluidframework/tree": "workspace:~" },
  }),
  "packages/framework/src/index.ts": "export const sdk = true;",
  "packages/tree/package.json": pkg("@fluidframework/tree"),
  "packages/tree/src/index.ts": "export class Tree {}",
  "packages/tree/src/test/answer.spec.ts": "hidden SDK test",
  "packages/tree/README.md": "Public API documentation",
  "packages/tree/examples/incident-board.ts": "must not stage",
  "packages/tree/src/cjs/package.json": '{"name":"@fluidframework/tree","type":"commonjs"}',
  "packages/azure-client/package.json": pkg("@fluidframework/azure-client"),
  "packages/test-runtime-utils/package.json": pkg("@fluidframework/test-runtime-utils"),
  "azure/packages/azure-local-service/package.json": pkg("@fluidframework/azure-local-service", {
    dependencies: { tinylicious: "^7.0.1" }, bin: "index.js",
  }),
  "azure/packages/azure-local-service/index.js": "import 'tinylicious';",
  "server/tinylicious/package.json": JSON.stringify({ name: "tinylicious", version: "8.0.0" }),
  "validation/solutions/model.ts": "answer",
};

test("Fluid selects the versioned local runtime closure, not nested metadata or unrelated server versions", async t => {
  const { root, revision } = await source(t, fluidFiles);
  const sdk = await resolveSdk({ sdk: "fluid", source: root, revision });
  assert.equal(sdk.revision, revision);
  assert.deepEqual(sdk.packages.map(value => value.name).sort(), [
    "@fluidframework/azure-client", "@fluidframework/azure-local-service",
    "@fluidframework/test-runtime-utils", "@fluidframework/tree", "fluid-framework",
  ]);
  assert.ok(sdk.sourceFiles.includes("packages/tree/src/index.ts"));
  assert.ok(sdk.sourceFiles.includes("azure/packages/azure-local-service/index.js"));
  assert.ok(sdk.docs.includes("packages/tree/README.md"));
  assert.ok(![...sdk.sourceFiles, ...sdk.docs].some(path =>
    /(^|\/)(test|examples|validation|\.git)(\/|$)/.test(path)));
  assert.equal(sdk.toolchain.packageManager, "pnpm@11.15.1");
});

test("Fluid rejects dirty source and a revision other than its checked-out build input", async t => {
  const { root, revision } = await source(t, fluidFiles);
  await writeFile(join(root, "packages/tree/src/index.ts"), "changed API");
  await assert.rejects(resolveSdk({ sdk: "fluid", source: root, revision }), /dirty|modified/i);
  await exec("git", ["add", "."], { cwd: root });
  await exec("git", ["-c", "user.name=Eval fixture", "-c", "user.email=eval@example.invalid",
    "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "Changed SDK"], { cwd: root });
  await assert.rejects(resolveSdk({ sdk: "fluid", source: root, revision }), /checked.out|HEAD/i);
});

test("Fluid rejects unresolved workspace dependencies and mixed client versions", async t => {
  for (const replacement of [
    pkg("fluid-framework", { dependencies: { "missing-local": "workspace:*" } }),
    JSON.stringify({ name: "fluid-framework", version: "3.2.0" }),
  ]) {
    const { root, revision } = await source(t, {
      ...fluidFiles, "packages/framework/package.json": replacement,
    });
    await assert.rejects(resolveSdk({ sdk: "fluid", source: root, revision }), /workspace|version/i);
  }
});

test("SDK selection rejects source symlinks instead of following files outside the checkout", async t => {
  const { root } = await source(t, fluidFiles);
  await symlink("../../../../outside", join(root, "packages/tree/src/escape.ts"));
  await exec("git", ["add", "."], { cwd: root });
  await exec("git", ["-c", "user.name=Eval fixture", "-c", "user.email=eval@example.invalid",
    "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "Symlink fixture"], { cwd: root });
  const revision = (await exec("git", ["rev-parse", "HEAD"], { cwd: root })).stdout.trim();
  await assert.rejects(resolveSdk({ sdk: "fluid", source: root, revision }), /symlink/i);
});

test("Fluid ignores untracked SDK tests but rejects untracked runtime build inputs", async t => {
  const { root, revision } = await source(t, fluidFiles);
  await writeFile(join(root, "packages/tree/src/test/oracle.spec.ts"), "private oracle");
  assert.ok(!(await resolveSdk({ sdk: "fluid", source: root, revision }))
    .sourceFiles.some(path => path.includes("oracle")));
  await writeFile(join(root, "packages/tree/src/untracked-api.ts"), "uncommitted runtime code");
  await assert.rejects(resolveSdk({ sdk: "fluid", source: root, revision }), /untracked.*runtime/i);
});

test("Watershed resolves an immutable allowlisted commit without trusting dirty working files", async t => {
  const { root, revision } = await source(t, {
    "gleam.toml": 'name = "watershed"\nversion = "1.0.0"\ngleam = ">= 1.11.0"\n',
    "manifest.toml": "# SDK dependency lock",
    "src/watershed/tree.gleam": "pub fn native_tree() { Nil }",
    "watershed_lustre/gleam.toml": 'name = "watershed_lustre"\nversion = "1.0.0"\n',
    "watershed_lustre/manifest.toml": "# Lustre dependency lock",
    "watershed_lustre/src/watershed_lustre/tree.gleam": "pub fn view() { Nil }",
    "docs/shared-tree-schema-authoring.md": "API guide",
    "evals/shared-tree-app/validation/solutions/model.gleam": "answer",
    "test/tree_test.gleam": "SDK tests",
  });
  await writeFile(join(root, "gleam.toml"), "invalid uncommitted change");
  const sdk = await resolveSdk({ sdk: "watershed", source: root, revision });
  assert.equal(sdk.packages[0].version, "1.0.0");
  assert.equal(sdk.toolchain.gleam, ">= 1.11.0");
  assert.ok(sdk.sourceFiles.includes("watershed_lustre/src/watershed_lustre/tree.gleam"));
  assert.deepEqual(sdk.docs, ["docs/shared-tree-schema-authoring.md"]);
  assert.ok(!sdk.sourceFiles.some(path => /(^|\/)(test|evals|validation)(\/|$)/.test(path)));
});
