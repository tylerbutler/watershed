import assert from "node:assert/strict";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { execOwned } from "../lib/process.mjs";
import { wait } from "../lib/conditions.mjs";

test("owned subprocess deadlines terminate a detached-stdio descendant that ignores SIGTERM", async () => {
  const root = await mkdtemp(join(tmpdir(), "shared-tree-process-"));
  let descendant;
  try {
    const pidFile = join(root, "descendant.pid");
    const pending = execOwned(process.execPath, ["--input-type=module", "-e", `
import { spawn } from "node:child_process";
const child = spawn(process.execPath, ["--input-type=module", "-e",
  'import {writeFileSync} from "node:fs"; process.on("SIGTERM",()=>{}); writeFileSync(process.argv[1], String(process.pid)); setInterval(()=>{},1000)',
  ${JSON.stringify(pidFile)}], {stdio:"ignore"});
setInterval(()=>{},1000);
`], { timeout: 1000, killGraceMs: 50 });
    const result = assert.rejects(pending, /timed out/);
    descendant = Number(await wait("descendant PID", async () => {
      try { return await readFile(pidFile, "utf8"); }
      catch (error) { if (error.code === "ENOENT") return false; throw error; }
    }, Boolean));
    await result;
    assert.throws(() => process.kill(descendant, 0), { code: "ESRCH" });
  } finally {
    if (descendant) {
      try { process.kill(descendant, "SIGKILL"); }
      catch (error) { if (error.code !== "ESRCH") throw error; }
    }
    await rm(root, { recursive: true, force: true });
  }
});

test("owned subprocess cancellation waits for exit", async () => {
  const controller = new AbortController();
  const child = execOwned(process.execPath, ["-e", 'console.log("started"); setInterval(()=>{},1000)'],
    { signal: controller.signal, killGraceMs: 50 });
  const aborted = assert.rejects(child, error => {
    assert.equal(error.name, "AbortError");
    return true;
  });
  controller.abort();
  await aborted;
});

test("owned subprocess failures preserve actionable stderr with the exit status", async () => {
  await assert.rejects(execOwned(process.execPath, ["-e", 'console.error("compiler fixture failed"); process.exit(7)']),
    error => {
      assert.equal(error.code, 7);
      assert.match(error.message, /compiler fixture failed/);
      assert.match(error.stderr, /compiler fixture failed/);
      return true;
    });
});
