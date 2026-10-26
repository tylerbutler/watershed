import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdir, mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { startServices } from "../lib/services.mjs";
import { execOwned } from "../lib/process.mjs";

test("invalid external origins and app ports fail before starting service resources", async () => {
  for (const options of [
    { serviceEndpoint: "http://user:password@localhost" },
    { serviceEndpoint: "http://localhost/not-an-origin" },
    { serviceEndpoint: "http://localhost?query=unexpected" },
    { serviceEndpoint: "file:///tmp" },
    { appPort: "-1" }, { appPort: "not-a-port" }, { appPort: 65536 },
  ]) {
    await assert.rejects(startServices({
      sdk: "watershed", root: tmpdir(), runId: "invalid-options", ...options,
    }), TypeError);
  }
});

for (const sdk of ["watershed", "fluid"]) {
  test(`${sdk} uses an externally owned service without an engine socket or local SDK server`, async t => {
    const root = await mkdtemp(join(tmpdir(), "incident-external-"));
    let services;
    let upstream;
    let unavailable = false;
    t.after(async () => {
      try { await services?.close(); }
      finally {
        if (upstream?.listening) {
          upstream.closeAllConnections();
          await new Promise(resolve => upstream.close(resolve));
        }
        await rm(root, { recursive: true, force: true });
      }
    });
    await mkdir(join(root, "dist"));
    await writeFile(join(root, "dist/index.html"), "<title>External service</title>");
    upstream = createServer((request, response) => {
      response.writeHead(unavailable ? 503 : 200, { "content-type": "application/json" })
        .end(JSON.stringify({ path: request.url }));
    });
    upstream.listen(0, "127.0.0.1");
    await once(upstream, "listening");
    const endpoint = `http://127.0.0.1:${upstream.address().port}`;
    services = await startServices({
      sdk, root, runId: "external-validation", serviceEndpoint: endpoint,
      stateRoot: tmpdir(),
    });
    assert.equal(await services.health(), true);
    assert.equal((await fetch(services.appUrl)).status, 200);
    assert.deepEqual(await (await fetch(new URL("/api/fixture", services.appUrl))).json(), { path: "/fixture" });
    assert.equal(services.diagnostics().endpoint, endpoint);
    assert.equal(services.diagnostics().dataRoot.startsWith(root), false);
    unavailable = true;
    assert.equal(await services.health(), false, "An independent service failure must remain observable");
    unavailable = false;
    await services.close();
    assert.equal((await fetch(endpoint)).status, 200, "The external service belongs to its Compose role, not this proxy");
  });
}

test("forced disconnection blocks pending and new Socket.IO polling until connections are restored", async t => {
  const root = await mkdtemp(join(tmpdir(), "incident-disconnection-"));
  await mkdir(join(root, "dist"));
  await writeFile(join(root, "dist/index.html"), "<title>Disconnected app</title>");
  let services;
  const upstream = createServer((request, response) => {
    request.resume();
    if (request.url.includes("hold=1")) {
      upstream.emit("polling");
      return;
    }
    response.end("available");
  });
  const controller = new AbortController();
  t.after(async () => {
    controller.abort();
    upstream.closeAllConnections();
    await services?.close();
    await new Promise(resolve => upstream.close(resolve));
    await rm(root, { recursive: true, force: true });
  });
  upstream.listen(0, "127.0.0.1");
  await once(upstream, "listening");
  services = await startServices({ sdk: "fluid", root, runId: "disconnection-polling",
    serviceEndpoint: `http://127.0.0.1:${upstream.address().port}`, appPort: 0 });
  const pending = once(upstream, "polling");
  const request = fetch(new URL("/socket.io/?transport=polling&hold=1", services.appUrl),
    { signal: controller.signal }).then(response => response.status, error => error.name);
  await pending;
  services.failConnections(true);
  for (const path of ["/socket.io/?transport=polling", "/api/socket.io/?transport=polling"]) {
    for (const method of ["GET", "POST"]) {
      const response = await fetch(new URL(path, services.appUrl), { method });
      assert.equal(response.status, 503, `${method} ${path} must not bypass the forced outage`);
      await response.body.cancel();
    }
  }
  assert.equal(await request, 503, "An active long poll must end when the outage starts");
  assert.equal(await services.health(), true, "The independent service health probe must still work");
  const app = await fetch(services.appUrl);
  assert.equal(app.status, 200, "Fault injection must leave the app available to display the error");
  await app.body.cancel();
  services.failConnections(false);
  const recovered = await fetch(new URL("/socket.io/?transport=polling", services.appUrl));
  assert.equal(recovered.status, 200);
  assert.equal(await recovered.text(), "available");
});

test("failed native service startup removes its owned state and proxy", async t => {
  const root = await mkdtemp(join(tmpdir(), "incident-startup-failure-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  await assert.rejects(startServices({ sdk: "fluid", root, runId: "startup-failure" }),
    /Fluid service exited/);
  assert.deepEqual(await readdir(root), []);
  const env = { ...process.env };
  delete env.SHARED_TREE_SERVICE_URL;
  await assert.rejects(execOwned(process.execPath, ["--input-type=module", "-e", `
import {startServices} from ${JSON.stringify(new URL("../lib/services.mjs", import.meta.url).href)};
try { await startServices({sdk:"fluid",root:${JSON.stringify(root)},stateRoot:${JSON.stringify(root)},
  appPort:0,runId:"startup-exit"}); } catch(error) { console.error(error.message); process.exitCode=2; }
`], { env, timeout: 3000, killGraceMs: 50 }), error => {
    assert.equal(error.code, 2, "No readiness-polling timer may outlive a failed service process");
    return true;
  });
});

test("service readiness retries a timed-out health request and later reports an outage", async t => {
  const root = await mkdtemp(join(tmpdir(), "shared-tree-health-"));
  let services;
  let requests = 0;
  let unavailable = false;
  const upstream = createServer((request, response) => {
    if (++requests === 1 || unavailable === "timeout") return;
    if (unavailable === "reset") {
      request.socket.destroy();
      return;
    }
    response.end("ready");
  });
  t.after(async () => {
    await services?.close();
    upstream.closeAllConnections();
    await new Promise(resolve => upstream.close(resolve));
    await rm(root, { recursive: true, force: true });
  });
  upstream.listen(0, "127.0.0.1");
  await once(upstream, "listening");
  services = await startServices({ sdk: "fluid", root, runId: "health-timeout",
    serviceEndpoint: `http://127.0.0.1:${upstream.address().port}`, appPort: 0 });
  assert.ok(requests >= 2);
  assert.equal(await services.health(), true);
  unavailable = "reset";
  assert.equal(await services.health(), false);
  unavailable = "timeout";
  assert.equal(await services.health(), false);
});
