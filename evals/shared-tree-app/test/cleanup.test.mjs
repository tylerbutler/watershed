import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { cleanupVallyRun } from "../lib/isolation.mjs";

async function fixture(t, mismatch = false) {
  const root = await mkdtemp(join(tmpdir(), "shared-tree-cleanup-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  await mkdir(join(root, "bin"));
  const state = join(root, "state.json");
  await writeFile(state, JSON.stringify({ container: true, network: true, volume: true }));
  await writeFile(join(root, "bin/docker"), `#!${process.execPath}
import {readFileSync,writeFileSync,appendFileSync} from "node:fs";
const [kind,command,...args]=process.argv.slice(2);
const state=JSON.parse(readFileSync(${JSON.stringify(state)}));
if(command==="ls"){
  const expected=kind==="volume"?"com.microsoft.vally.run":"com.watershed.shared-tree-eval.run";
  if(state[kind] && args.includes("label="+expected+"=owned-run")) console.log("owned-"+kind);
}else if(command==="inspect"){
  const labels={"com.microsoft.vally.run":${JSON.stringify(mismatch ? "another-run" : "owned-run")},
    "com.watershed.shared-tree-eval.run":${JSON.stringify(mismatch ? "another-run" : "owned-run")}};
  console.log(JSON.stringify([{Labels:labels,Config:{Labels:labels}}]));
}else if(command==="rm"){
  appendFileSync(${JSON.stringify(join(root, "removed.log"))},kind+"\\n");
  state[kind]=false; writeFileSync(${JSON.stringify(state)},JSON.stringify(state));
}else process.exit(99);
`, { mode: 0o700 });
  return { root, env: { ...process.env, PATH: `${join(root, "bin")}:${process.env.PATH}` } };
}

test("interrupted-run cleanup removes owned runtime resources but preserves recovery volumes", async t => {
  const { root, env } = await fixture(t);
  const result = await cleanupVallyRun({ runId: "owned-run", env });
  assert.equal(result.removed.length, 2);
  assert.deepEqual(result.preserved, [{ kind: "volume", id: "owned-volume" }]);
  assert.deepEqual((await readFile(join(root, "removed.log"), "utf8")).trim().split("\n"),
    ["container", "network"]);
  assert.equal(JSON.parse(await readFile(join(root, "state.json"), "utf8")).volume, true);
  const repeated = await cleanupVallyRun({ runId: "owned-run", env });
  assert.deepEqual(repeated.removed, []);
  assert.deepEqual(repeated.preserved, [{ kind: "volume", id: "owned-volume" }]);
});

test("cleanup refuses a mismatched inspected owner before deleting anything", async t => {
  const { root, env } = await fixture(t, true);
  await assert.rejects(cleanupVallyRun({ runId: "owned-run", env }), /owner|label/i);
  await assert.rejects(readFile(join(root, "removed.log")), { code: "ENOENT" });
});
