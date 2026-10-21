import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { cp, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import test from "node:test";
import { grade } from "../graders/main.mjs";
import { createIntegrityManifest } from "../lib/staging.mjs";
import { validateReport, verdict } from "../lib/report.mjs";

const contract = JSON.parse(await readFile(new URL("../contract.json", import.meta.url), "utf8"));
const exec = promisify(execFile);

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), "incident-grade-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const workspace = join(root, "agent");
  const gradingRoot = join(root, "grading");
  await mkdir(join(workspace, "src"), { recursive: true });
  await mkdir(join(workspace, "sdk"));
  await mkdir(gradingRoot);
  for (const [path, value] of Object.entries({
    "src/model.ts": "candidate", "src/schema.ts": "schema", "sdk/native.js": "protected SDK",
    "package.json": '{"scripts":{"check":"node -e process.exit(89)","build":"node -e process.exit(89)"}}',
  })) await writeFile(join(workspace, path), value);
  const manifest = await createIntegrityManifest({ workspace, sdk: "fluid" });
  await writeFile(join(gradingRoot, "integrity.json"), JSON.stringify(manifest));
  await writeFile(join(gradingRoot, "sdk.json"), '{"version":1,"sdk":"fluid"}');
  await cp(workspace, join(gradingRoot, "workspace"), { recursive: true });
  return { root, workspace, gradingRoot, output: join(root, "artifacts/report.json") };
}

test("protected edits produce a complete persisted failing report without running candidate scripts", async t => {
  const { workspace, gradingRoot, output } = await fixture(t);
  await writeFile(join(workspace, "package.json"), '{"scripts":{"check":"untrusted command"}}');
  const report = await grade({ sdk: "fluid", workspace, gradingRoot, runId: "protected-edit", output });
  assert.equal(verdict(report, contract), "failed");
  assert.equal(report.classification, "agent");
  assert.equal(report.checks.find(check => check.id === "integrity.assets").passed, false);
  assert.equal(report.checks.find(check => check.id === "integrity.sdk").passed, true);
  assert.match(report.checks.find(check => check.id === "integrity.build").evidence, /not reached|integrity/i);
  const stored = JSON.parse(await readFile(output, "utf8"));
  assert.deepEqual(stored, report);
  validateReport(stored, contract);
  await assert.rejects(grade({ sdk: "fluid", workspace, gradingRoot, runId: "must-not-replace", output }),
    /exist|EEXIST/i);
  assert.deepEqual(JSON.parse(await readFile(output, "utf8")), stored);
  await assert.rejects(exec(process.execPath, [
    fileURLToPath(new URL("../graders/main.mjs", import.meta.url)), "--sdk", "fluid",
    "--workspace", workspace, "--grading-root", gradingRoot, "--run-id", "protected-cli",
    "--output", `${output}.cli`,
  ]), error => {
    assert.equal(error.code, 1);
    assert.equal(error.stdout.includes("SHARED_TREE_EVAL_ALL_REQUIRED_PASSED"), false);
    return true;
  });
  validateReport(JSON.parse(await readFile(`${output}.cli`, "utf8")), contract);
});

test("a damaged trusted baseline is invalid infrastructure, not an agent failure", async t => {
  const { workspace, gradingRoot, output } = await fixture(t);
  await writeFile(join(gradingRoot, "workspace/sdk/native.js"), "damaged baseline");
  const report = await grade({ sdk: "fluid", workspace, gradingRoot, runId: "bad-baseline", output });
  validateReport(report, contract);
  assert.equal(verdict(report, contract), "invalid");
  assert.match(report.checks[0].evidence, /trusted baseline integrity failed/i);
});

test("cancelled grading publishes an infrastructure report rather than starting candidate work", async t => {
  const { workspace, gradingRoot, output } = await fixture(t);
  const controller = new AbortController();
  controller.abort(new Error("Injected grading interruption"));
  const report = await grade({
    sdk: "fluid", workspace, gradingRoot, runId: "interrupted-grade", output, signal: controller.signal,
  });
  assert.equal(verdict(report, contract), "invalid");
  assert.ok(report.checks.every(check => !check.passed));
  assert.match(report.checks[0].evidence, /injected grading interruption/i);
});

test("an unwritable output path cannot publish a passing marker or overwrite evidence", async t => {
  const { root, workspace, gradingRoot } = await fixture(t);
  const blocked = join(root, "not-a-directory");
  await writeFile(blocked, "retained evidence");
  await assert.rejects(exec(process.execPath, [
    fileURLToPath(new URL("../graders/main.mjs", import.meta.url)), "--sdk", "fluid",
    "--workspace", workspace, "--grading-root", gradingRoot, "--run-id", "output-failure",
    "--output", join(blocked, "report.json"),
  ]), error => {
    assert.equal(error.code, 2);
    assert.equal(error.stdout.includes("SHARED_TREE_EVAL_ALL_REQUIRED_PASSED"), false);
    return true;
  });
  assert.equal(await readFile(blocked, "utf8"), "retained evidence");
});
