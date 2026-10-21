import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { launchBrowser } from "../lib/cdp.mjs";
import { wait } from "../lib/conditions.mjs";

test("browser shutdown requests native cleanup before removing a profile used by descendants", async () => {
  const root = await mkdtemp(join(tmpdir(), "shared-tree-browser-close-"));
  let browser;
  let descendant;
  try {
    const executable = join(root, "chromium-fixture");
    const pidFile = join(root, "descendant.pid");
    await writeFile(executable, `#!${process.execPath}
import {spawn} from "node:child_process";
import {once} from "node:events";
import {writeFileSync} from "node:fs";
import {WebSocketServer} from ${JSON.stringify(import.meta.resolve("ws"))};
const child=spawn(process.execPath,["-e","setInterval(()=>{},1000)"],{stdio:"ignore"});
writeFileSync(${JSON.stringify(pidFile)},String(child.pid));
const server=new WebSocketServer({host:"127.0.0.1",port:0});
await once(server,"listening");
console.error("DevTools listening on ws://127.0.0.1:"+server.address().port);
server.on("connection",socket=>socket.on("message",async data=>{
  const message=JSON.parse(data);
  socket.send(JSON.stringify({id:message.id,result:{}}));
  if(message.method==="Browser.close"){
    const exited=once(child,"exit"); child.kill("SIGTERM"); await exited;
    socket.close(); server.close(()=>process.exit(0));
  }
}));
`, { mode: 0o700 });
    browser = await launchBrowser({ executable });
    descendant = Number(await wait("browser descendant", async () => {
      try { return await readFile(pidFile, "utf8"); }
      catch (error) { if (error.code === "ENOENT") return false; throw error; }
    }, Boolean));
    await browser.close();
    assert.throws(() => process.kill(descendant, 0), { code: "ESRCH" });
  } finally {
    if (browser) await browser.close();
    if (descendant) {
      try { process.kill(descendant, "SIGKILL"); }
      catch (error) { if (error.code !== "ESRCH") throw error; }
    }
    await rm(root, { recursive: true, force: true });
  }
});

test("missing Chromium fails explicitly rather than passing a browser preflight", async () => {
  const root = await mkdtemp(join(tmpdir(), "shared-tree-browser-missing-"));
  try {
    await assert.rejects(launchBrowser({ executable: join(root, "missing-chromium") }), /ENOENT|spawn/);
  } finally { await rm(root, { recursive: true, force: true }); }
});
