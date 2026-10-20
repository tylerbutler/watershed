import assert from "node:assert/strict";
import test from "node:test";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { access, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { bounded, wait } from "../../lib/conditions.mjs";

test("development host cleans up when interrupted during service startup", async () => {
  const root = await mkdtemp(join(tmpdir(), "incident-serve-test-"));
  const pidFile = join(root, "owned-service-pid");
  let child;
  try {
    const entry = join(root, "node_modules/@fluidframework/azure-local-service");
    await mkdir(entry, { recursive: true });
    await writeFile(join(entry, "index.js"), `
const { writeFileSync } = require("node:fs");
const { createServer } = require("node:http");
writeFileSync(${JSON.stringify(pidFile)}, String(process.pid));
setTimeout(() => createServer((req, res) => res.end("ok"))
  .listen(Number(process.env.PORT), "127.0.0.1"), 1000);
`);
    child = spawn(process.execPath, [
      fileURLToPath(new URL("../../public/serve.mjs", import.meta.url)),
      "--sdk", "fluid", "--root", root,
    ], { stdio: ["ignore", "pipe", "pipe"] });
    const exited = once(child, "exit");
    let diagnostics = "";
    child.stderr.on("data", chunk => { diagnostics += chunk; });
    await wait("service process allocated before readiness", async () => {
      try { await access(pidFile); return true; }
      catch (error) { if (error.code === "ENOENT") return false; throw error; }
    }, Boolean);
    child.kill("SIGTERM");
    const [code, signal] = await bounded("interrupted host cleanup", () => exited, 10_000);
    assert.equal(signal, null, diagnostics);
    assert.equal(code, 0, diagnostics);
    assert.deepEqual((await readdir(root)).filter(name => name.startsWith(".service-")), []);
  } finally {
    if (child && child.exitCode === null && child.signalCode === null) {
      const exited = once(child, "exit");
      child.kill("SIGKILL");
      await bounded("test host cleanup", () => exited);
    }
    let pid;
    try { pid = Number(await readFile(pidFile, "utf8")); }
    catch (error) { if (error.code !== "ENOENT") throw error; }
    if (pid) {
      try { process.kill(pid, "SIGTERM"); }
      catch (error) { if (error.code !== "ESRCH") throw error; }
    }
    await rm(root, { recursive: true, force: true });
  }
});
