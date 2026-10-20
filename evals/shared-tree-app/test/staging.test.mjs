import assert from "node:assert/strict";
import test from "node:test";
import { mkdtemp, mkdir, writeFile, readFile, symlink, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createIntegrityManifest, verifyIntegrity, overlayCandidate } from "../lib/staging.mjs";

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), "incident-integrity-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const workspace = join(root, "agent");
  const trusted = join(root, "trusted");
  for (const name of ["src", "sdk", "test"]) await mkdir(join(workspace, name), { recursive: true });
  await mkdir(join(trusted, "src"), { recursive: true });
  for (const [name, content] of [
    ["src/model.ts", "candidate model"], ["src/schema.ts", "candidate schema"],
    ["src/App.tsx", "protected shell"], ["package.json", '{"private":true}'],
    ["sdk/native.js", "selected SDK"],
  ]) await writeFile(join(workspace, name), content);
  await writeFile(join(trusted, "src/App.tsx"), "trusted shell");
  return { root: workspace, trusted };
}

test("integrity accepts candidate models and tests but detects shell, dependency, and SDK edits", async t => {
  const { root } = await fixture(t);
  const manifest = await createIntegrityManifest({ workspace: root, sdk: "fluid" });
  await writeFile(join(root, "src/model.ts"), "new candidate model");
  await writeFile(join(root, "test/candidate.test.mjs"), "candidate test");
  assert.equal((await verifyIntegrity({ workspace: root, manifest })).passed, true);
  await writeFile(join(root, "src/App.tsx"), "changed shell");
  let result = await verifyIntegrity({ workspace: root, manifest });
  assert.equal(result.assetsPassed, false);
  assert.equal(result.sdkPassed, true);
  await writeFile(join(root, "sdk/native.js"), "modified SDK");
  result = await verifyIntegrity({ workspace: root, manifest });
  assert.equal(result.sdkPassed, false);
  assert.match(result.evidence, /src\/App\.tsx/);
  assert.match(result.evidence, /sdk\/native\.js/);
});

test("integrity rejects unexpected source files and symlink escapes in candidate-owned tests", async t => {
  const { root } = await fixture(t);
  const manifest = await createIntegrityManifest({ workspace: root, sdk: "fluid" });
  await writeFile(join(root, "src/shell-helper.ts"), "unexpected source");
  assert.equal((await verifyIntegrity({ workspace: root, manifest })).passed, false);
  await rm(join(root, "src/shell-helper.ts"));
  await symlink(join(root, "package.json"), join(root, "test/escape.mjs"));
  const result = await verifyIntegrity({ workspace: root, manifest });
  assert.equal(result.passed, false);
  assert.match(result.evidence, /symlink.*test\/escape\.mjs/i);
});

test("grading overlay copies only candidate-owned sources, never generated output or build scripts", async t => {
  const { root, trusted } = await fixture(t);
  const manifest = await createIntegrityManifest({ workspace: root, sdk: "fluid" });
  await mkdir(join(root, "dist"));
  await writeFile(join(root, "dist/app.js"), "untrusted built output");
  await writeFile(join(root, "src/model.ts"), "new candidate");
  await overlayCandidate({ workspace: root, manifest, trusted });
  assert.equal(await readFile(join(trusted, "src/model.ts"), "utf8"), "new candidate");
  assert.equal(await readFile(join(trusted, "src/App.tsx"), "utf8"), "trusted shell");
  await assert.rejects(readFile(join(trusted, "dist/app.js")), { code: "ENOENT" });
  await writeFile(join(root, "package.json"), '{"scripts":{"build":"untrusted"}}');
  await assert.rejects(overlayCandidate({ workspace: root, manifest, trusted }),
    /integrity/i);
});

test("integrity rejects malformed manifests and paths escaping the selected workspace", async t => {
  const { root } = await fixture(t);
  const manifest = await createIntegrityManifest({ workspace: root, sdk: "fluid" });
  manifest.files.push({ path: "../outside", sha256: "0".repeat(64) });
  await assert.rejects(verifyIntegrity({ workspace: root, manifest }), /path/i);
});

test("integrity rejects a symlink replacing a protected source directory", async t => {
  const { root, trusted } = await fixture(t);
  const manifest = await createIntegrityManifest({ workspace: root, sdk: "fluid" });
  await rm(join(root, "src"), { recursive: true });
  await symlink(join(trusted, "src"), join(root, "src"));
  const result = await verifyIntegrity({ workspace: root, manifest });
  assert.equal(result.assetsPassed, false);
  assert.match(result.evidence, /symlink.*src/i);
  await assert.rejects(overlayCandidate({ workspace: root, manifest, trusted }), /integrity/i);
});

test("grading refuses an agent-controlled grading destination", async t => {
  const { root } = await fixture(t);
  const manifest = await createIntegrityManifest({ workspace: root, sdk: "fluid" });
  await mkdir(join(root, "grade"));
  await assert.rejects(overlayCandidate({ workspace: root, manifest, trusted: join(root, "grade") }),
    /separate|outside/i);
});

test("missing candidate sources cannot inherit trusted model implementations", async t => {
  const { root, trusted } = await fixture(t);
  const manifest = await createIntegrityManifest({ workspace: root, sdk: "fluid" });
  await rm(join(root, "src/model.ts"));
  assert.equal((await verifyIntegrity({ workspace: root, manifest })).passed, false);
  await assert.rejects(overlayCandidate({ workspace: root, manifest, trusted }), /integrity/i);
});
