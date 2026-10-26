import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { cp, mkdir, mkdtemp, readFile, readdir, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import test from "node:test";
import { prepare } from "../prepare.mjs";
import { verifyIntegrity } from "../lib/staging.mjs";

const exec = promisify(execFile);
const benchmark = fileURLToPath(new URL("../", import.meta.url));

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), "incident-prepare-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const source = join(root, "host");
  for (const [path, content] of Object.entries({
    "gleam.toml": 'name = "watershed"\nversion = "0.1.0"\ngleam = ">= 1.7.0"\n',
    "manifest.toml": "# locked SDK",
    "src/watershed/tree.gleam": "pub fn native() { Nil }",
    "watershed_lustre/gleam.toml": 'name = "watershed_lustre"\nversion = "0.1.0"\n',
    "watershed_lustre/manifest.toml": "# locked Lustre",
    "watershed_lustre/src/watershed_lustre/tree.gleam": "pub fn native() { Nil }",
    "docs/shared-tree-schema-authoring.md": "Public API guide",
    "validation/solutions/model.gleam": "must not stage",
  })) {
    await mkdir(dirname(join(source, path)), { recursive: true });
    await writeFile(join(source, path), content);
  }
  await exec("git", ["init", "--quiet"], { cwd: source });
  await exec("git", ["add", "."], { cwd: source });
  await exec("git", ["-c", "user.name=Eval fixture", "-c", "user.email=eval@example.invalid",
    "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "SDK fixture"], { cwd: source });
  const revision = (await exec("git", ["rev-parse", "HEAD"], { cwd: source })).stdout.trim();
  return { root, source, revision };
}

test("preparation separates hidden assets and keeps all Gleam path dependencies inside the agent root", async t => {
  const { root, source, revision } = await fixture(t);
  const prepared = await prepare({ sdk: "watershed", source, revision, out: join(root, "out") });
  const files = await readdir(prepared.agentRoot, { recursive: true });
  assert.ok(files.includes("src/incident_eval/model.gleam"));
  assert.ok(files.includes("sdk/watershed/src/watershed/tree.gleam"));
  assert.equal(files.some(path =>
    /(^|\/)(\.git|validation|graders|examples)(\/|$)/.test(path)), false);
  assert.equal(files.includes("src/model.ts"), false);
  const manifest = await readFile(join(prepared.agentRoot, "gleam.toml"), "utf8");
  const lock = await readFile(join(prepared.agentRoot, "manifest.toml"), "utf8");
  assert.match(manifest, /path = "sdk\/watershed"/);
  assert.match(manifest, /path = "sdk\/watershed\/watershed_lustre"/);
  assert.equal(manifest.includes("../sdk"), false);
  assert.equal(lock.includes("../sdk"), false);
  assert.equal((await verifyIntegrity({
    workspace: prepared.agentRoot, manifest: prepared.integrityManifest,
  })).passed, true);
  await writeFile(join(prepared.agentRoot, "src/incident_eval/model.gleam"), "candidate change");
  assert.notEqual(await readFile(join(prepared.gradingRoot, "workspace/src/incident_eval/model.gleam"), "utf8"),
    "candidate change");
  assert.ok((await readdir(join(prepared.gradingRoot, "graders"))).includes("scenarios.mjs"));
  assert.equal(prepared.sdkManifest.revision, revision);
  assert.ok(prepared.docsManifest.files.some(file => file.path.endsWith("shared-tree-schema-authoring.md")));
});

test("preparation works from a relocated standalone benchmark rather than a host example layout", async t => {
  const { root, source, revision } = await fixture(t);
  const relocated = join(root, "standalone");
  await mkdir(relocated);
  for (const path of ["prepare.mjs", "lib", "graders", "docker", "watershed", "task.md", "contract.json",
    "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml"]) {
    await cp(join(benchmark, path), join(relocated, path), { recursive: true, filter: path =>
      !path.split("/").includes("node_modules") });
  }
  // Resolve the standalone package's existing tooling dependencies without copying them.
  await symlink(join(benchmark, "node_modules"), join(relocated, "node_modules"));
  const output = join(root, "relocated-out");
  await exec(process.execPath, [join(relocated, "prepare.mjs"), "--sdk", "watershed", "--source", source,
    "--revision", revision, "--out", output], { cwd: root, timeout: 30_000 });
  assert.ok((await readdir(join(output, "agent", "src/incident_eval"))).includes("model.gleam"));
});

test("transfer preparation overlays protected sources without exposing private reference models", async t => {
  const { root, source, revision } = await fixture(t);
  const prepared = await prepare({ sdk: "watershed", source, revision, out: join(root, "transfers"),
    track: "transfers" });
  assert.equal(prepared.track, "transfers");
  assert.equal(prepared.sdkManifest.track, "transfers");
  assert.match(await readFile(join(prepared.agentRoot, "src/incident_eval/domain.gleam"), "utf8"),
    /TransferStep/);
  assert.equal(await readFile(join(prepared.agentRoot, "src/incident_eval/model.gleam"), "utf8"),
    await readFile(join(benchmark, "watershed/src/incident_eval/model.gleam"), "utf8"));
  const contract = JSON.parse(await readFile(join(prepared.gradingRoot, "contract.json"), "utf8"));
  assert.ok(contract.checks.some(check => check.id === "transfers.concurrent-edit"));
  assert.ok(contract.checks.some(check => check.id === "concurrency.barrier"));
  assert.equal((await verifyIntegrity({ workspace: prepared.agentRoot,
    manifest: prepared.integrityManifest })).passed, true);
  await writeFile(join(prepared.agentRoot, "src/incident_eval/domain.gleam"), "remove transfer action");
  assert.equal((await verifyIntegrity({ workspace: prepared.agentRoot,
    manifest: prepared.integrityManifest })).assetsPassed, false);
  const files = await readdir(prepared.agentRoot, { recursive: true });
  assert.equal(files.some(path => /(^|\/)(validation|graders|tracks)(\/|$)/.test(path)), false);
});
