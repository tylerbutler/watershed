import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer } from "node:http";
import test from "node:test";
import {
  cleanupEphemeralService,
  startEphemeralService,
} from "@fluidframework/local-driver/alpha";
import { SharedMap } from "@fluidframework/map/internal";
import {
  preflight,
  serviceConfig,
  serviceStore,
  validatePreflight,
} from "./service.mjs";

test("the service bootstrap is a real SharedMap containing a hierarchical tree handle", {
  timeout: 30_000,
}, async () => {
  const service = startEphemeralService();
  try {
    const first = await service.defaultClient.createAttachedContainer(serviceStore);
    const second = await service.defaultClient.loadContainer(first.id, serviceStore);
    assert.equal(first.data.bootstrap.attributes.type, SharedMap.getFactory().type);
    assert(first.data.bootstrap.handle.absolutePath.endsWith("/root"));
    const handle = first.data.bootstrap.get("tree");
    assert.equal(await handle.get(), first.data.tree);
    assert(handle.absolutePath.split("/").filter(Boolean).length >= 2);
    first.data.view.root.title = "bootstrap";
    second.data.view.root.point.y = 9;
    await service.synchronize();
    assert.equal(second.data.view.root.title, "bootstrap");
    assert.equal(first.data.view.root.point.y, 9);
  } finally {
    await cleanupEphemeralService();
  }
});

test("service configuration requires explicit credentials and an immutable revision", () => {
  assert.throws(() => serviceConfig({}), /JWT_SECRET/);
  assert.throws(() => serviceConfig({ FLOODGATE_JWT_SECRET: "test-only" }), /REVISION/);
  const config = serviceConfig({
    FLOODGATE_JWT_SECRET: "test-only",
    FLOODGATE_REVISION: "0eb493fc46d1bb9baf1151a6ccdde93544e057e7",
    FLOODGATE_HTTP_URL: "http://127.0.0.1:3000/",
  });
  assert.equal(config.httpUrl, "http://127.0.0.1:3000");
  assert.equal(config.tenantId, "fluid");
  assert.throws(() => serviceConfig({
    FLOODGATE_JWT_SECRET: "test-only", FLOODGATE_REVISION: "main",
  }), /REVISION/);
});

function completedPreflight() {
  return {
    referenceVersion: "3.1.0",
    transportVerified: true,
    created: true,
    peerObservedEdit: true,
    summaryPublished: true,
    deltaStorageVerified: true,
    freshClientObservedEdit: true,
    nativeJavaScriptTransportVerified: true,
    nativeBeamTransportVerified: true,
    mockService: false,
  };
}

test("preflight validation refuses incomplete or mocked service evidence", () => {
  assert.doesNotThrow(() => validatePreflight(completedPreflight()));
  for (const field of [
    "transportVerified", "created", "peerObservedEdit", "summaryPublished", "deltaStorageVerified",
    "freshClientObservedEdit",
    "nativeJavaScriptTransportVerified", "nativeBeamTransportVerified",
  ]) {
    assert.throws(() => validatePreflight({
      ...completedPreflight(), [field]: false,
    }), new RegExp(field));
  }
  assert.throws(() => validatePreflight({
    ...completedPreflight(), mockService: true,
  }), /mockService/);
  assert.throws(() => validatePreflight({
    ...completedPreflight(), referenceVersion: "3.0.0",
  }), /referenceVersion/);
});

test("preflight reports an unavailable service as a failed health stage", async (t) => {
  const server = createServer((_request, response) => {
    response.writeHead(503).end("unavailable");
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  t.after(() => new Promise((resolve) => server.close(resolve)));
  const config = serviceConfig({
    FLOODGATE_JWT_SECRET: "test-only",
    FLOODGATE_REVISION: "0eb493fc46d1bb9baf1151a6ccdde93544e057e7",
    FLOODGATE_HTTP_URL: `http://127.0.0.1:${server.address().port}`,
  });
  await assert.rejects(preflight(config), /health.*503/);
});
