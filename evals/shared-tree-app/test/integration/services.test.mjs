import assert from "node:assert/strict";
import test from "node:test";
import { access, mkdir, mkdtemp, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { startServices } from "../../lib/services.mjs";

for (const sdk of ["fluid", "watershed"]) {
  test(`${sdk} service has fresh owned state and a responsive app origin`, async t => {
    const root = await mkdtemp(join(tmpdir(), "incident-service-test-"));
    let services;
    try {
      await mkdir(join(root, "dist"));
      await writeFile(join(root, "dist/index.html"), "<!doctype html><title>Fixture</title>");
      if (sdk === "fluid") {
        await symlink(fileURLToPath(new URL("../../fluid/node_modules", import.meta.url)), join(root, "node_modules"));
      }
      services = await startServices({ sdk, root, runId: "service-validation" });
      assert.equal(await services.health(), true);
      assert.equal((await fetch(services.appUrl)).status, 200);
      const url = new URL(services.appUrl);
      assert.equal(url.searchParams.has(sdk === "fluid" ? "endpoint" : "socket"), true);
      const diagnostics = services.diagnostics();
      assert.equal(diagnostics.sdk, sdk);
      assert.ok(diagnostics.dataRoot.startsWith(root));
      if (sdk === "watershed") {
        assert.match(diagnostics.imageId, /^sha256:[a-f0-9]{64}$/);
        assert.equal(diagnostics.serviceRevision, "21faeaa4867127cdf437d21c9b5cafc8f027d42d");
        assert.equal((await fetch(new URL("/api/health", services.appUrl))).status, 200);
      } else {
        const networkFetch = globalThis.fetch;
        t.mock.method(globalThis, "fetch", (target, options) => {
          if (target === `${diagnostics.endpoint}/interrupted`) {
            return Promise.resolve(new Response(new ReadableStream({
              start(controller) { controller.error(new Error("Upstream reset")); },
            })));
          }
          return networkFetch(target, options);
        });
        const failed = await networkFetch(new URL("/api/interrupted", services.appUrl), {
          signal: AbortSignal.timeout(5000),
        });
        assert.equal(failed.status, 502);
        assert.equal(await failed.text(), "Upstream reset");
        assert.equal(await services.health(), true);
      }
      await services.close();
      await services.close();
      await assert.rejects(access(diagnostics.dataRoot), { code: "ENOENT" });
      services = undefined;
    } finally {
      if (services) await services.close();
      await rm(root, { recursive: true, force: true });
    }
  });
}
