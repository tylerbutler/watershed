import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { startServices } from "../lib/services.mjs";

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
      response.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify({ path: request.url }));
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
    await services.close();
    assert.equal((await fetch(endpoint)).status, 200, "The external service belongs to its Compose role, not this proxy");
  });
}
