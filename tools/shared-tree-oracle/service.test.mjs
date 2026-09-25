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
  cleanupOwned,
  localFloodgateReady,
  preflight,
  observedDocumentServiceFactory,
  mapServiceStore,
  serviceConfig,
  serviceStore,
  runServiceCommand,
  validatePreflight,
} from "./service.mjs";

test("cleanup attempts every resource and attaches failures to the scenario error", () => {
  const calls = [];
  const scenario = new Error("scenario");
  const first = new Error("first cleanup");
  const third = new Error("third cleanup");
  cleanupOwned([
    { dispose() { calls.push("first"); throw first; } },
    { dispose() { calls.push("second"); } },
    { dispose() { calls.push("third"); throw third; } },
  ], scenario);
  assert.deepEqual(calls, ["first", "second", "third"]);
  assert.deepEqual(scenario.cleanupErrors, [first, third]);
  assert.throws(
    () => cleanupOwned([{ dispose() { throw first; } }]),
    (error) => error instanceof AggregateError && error.errors[0] === first,
  );
});

test("storage observation wraps real calls without replacing their results", async () => {
  const versions = [{ id: "commit", treeId: "tree" }];
  const snapshot = { id: "tree", blobs: { data: "blob" }, trees: {} };
  const bytes = Uint8Array.from([1, 2, 3]);
  const storage = {
    async getVersions() { return versions; },
    async getSnapshotTree() { return snapshot; },
    async readBlob() { return bytes; },
  };
  const service = {
    async connectToStorage() { return storage; },
    dispose() {},
  };
  const factory = {
    async createDocumentService() { return service; },
  };
  const observations = [];
  const wrapped = observedDocumentServiceFactory(factory, observations);
  const actualService = await wrapped.createDocumentService({ id: "document" });
  const actualStorage = await actualService.connectToStorage();
  assert.equal(await actualStorage.getVersions(null, 1), versions);
  assert.equal(await actualStorage.getSnapshotTree(), snapshot);
  assert.equal(await actualStorage.readBlob("blob"), bytes);
  assert.deepEqual(observations, [
    { operation: "createDocumentService", documentId: "document", result: "connected" },
    { operation: "connectToStorage", result: "connected" },
    {
      operation: "getVersions",
      count: 1,
      versions: [{ id: "commit", treeId: "tree" }],
    },
    {
      operation: "getSnapshotTree",
      id: "tree",
      blobs: ["data"],
      trees: [],
    },
    {
      operation: "readBlob",
      id: "blob",
      byteLength: 3,
      hash: "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81",
    },
  ]);
});

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

test("the map service store creates and reloads a dynamic map root", {
  timeout: 30_000,
}, async () => {
  const service = startEphemeralService();
  try {
    const first = await service.defaultClient.createAttachedContainer(mapServiceStore);
    const second = await service.defaultClient.loadContainer(first.id, mapServiceStore);
    assert.equal(first.data.bootstrap.attributes.type, SharedMap.getFactory().type);
    assert(first.data.bootstrap.handle.absolutePath.endsWith("/root"));
    assert.deepEqual([...first.data.view.root.items.entries()], []);

    first.data.view.root.items.set("", "empty");
    first.data.view.root.items.set("é", 7);
    first.data.view.root.items.set("__proto__", null);
    await service.synchronize();

    assert.equal(second.data.view.root.items.get(""), "empty");
    assert.equal(second.data.view.root.items.get("é"), 7);
    assert.equal(second.data.view.root.items.get("__proto__"), null);
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

test("service interop dispatches through a dynamic import and preserves preflight", async () => {
  const calls = [];
  await runServiceCommand(["interop", "--iterations", "200"], {
    importInterop: async () => ({
      runInteropCommand: async (args) => calls.push(["interop", args]),
    }),
  });
  await runServiceCommand(["preflight", "--local"], {
    runPreflight: async (args) => calls.push(["preflight", args]),
  });
  assert.deepEqual(calls, [
    ["interop", ["--iterations", "200"]],
    ["preflight", ["preflight", "--local"]],
  ]);
});

test("local Floodgate readiness retries transient loopback fetch failures", async () => {
  const child = { exitCode: null, signalCode: null };
  assert.equal(await localFloodgateReady(child, "http://127.0.0.1:1", {
    fetch: async () => {
      throw new TypeError("fetch failed", {
        cause: Object.assign(new Error("reset"), { code: "ECONNRESET" }),
      });
    },
  }), false);
  await assert.rejects(() => localFloodgateReady(
    { exitCode: 1, signalCode: null },
    "http://127.0.0.1:1",
    { fetch: async () => assert.fail("must not fetch") },
  ), /exited before becoming ready/);
});
