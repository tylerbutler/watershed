import assert from "node:assert/strict";
import { createHash } from "node:crypto";
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
  openSession,
  mapServiceStore,
  excludedFeatures,
  serviceConfig,
  serviceStore,
  supportedFeatures,
  runServiceCommand,
  validatePreflight,
  withLocalFloodgate,
} from "./service.mjs";
import { upstreamAdapter } from "./interop-scenarios.mjs";

test("service profile names supported transactions and their limits", () => {
  for (const feature of [
    "strict-view-object-map-schema-evolution",
    "identifier-summary-reload",
    "synchronous-single-tree-transactions",
    "stable-node-existence-constraints",
  ]) {
    assert(supportedFeatures.includes(feature), `Missing support: ${feature}`);
  }
  assert(!excludedFeatures.includes("schema-evolution"));
  assert(!excludedFeatures.includes("public-transactions"));
  for (const feature of [
    "staged-schema-upgrades",
    "array-schema-evolution",
    "unknown-field-view-adapters",
    "data-migrations",
    "additional-upstream-versions",
    "identifier-handles",
    "incremental-field-batch-chunks",
    "arbitrary-container-layouts",
    "tree-short-id",
    "identifier-index",
    "custom-identifier-global-uniqueness",
    "detached-node-builder",
    "uuidv5-healing",
    "undo-redo",
    "asynchronous-transactions",
    "cross-tree-transactions",
    "schema-upgrades-in-transactions",
    "no-change-constraints",
    "transaction-metadata",
    "transaction-post-processors",
    "async-cross-tree-transactions",
  ]) {
    assert(excludedFeatures.includes(feature), `Missing exclusion: ${feature}`);
  }
});

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
  assert.equal(await actualStorage.getSnapshotTree(versions[0]), snapshot);
  assert.equal(await actualStorage.readBlob("blob"), bytes);
  assert.deepEqual(observations, [
    { operation: "createDocumentService", documentId: "document", result: "connected" },
    { operation: "connectToStorage", result: "connected" },
    {
      operation: "getVersions",
      request: [null, 1],
      responseBody: Buffer.from(JSON.stringify(versions)).toString("base64"),
      hash: createHash("sha256").update(JSON.stringify(versions)).digest("hex"),
      count: 1,
      versions: [{ id: "commit", treeId: "tree" }],
    },
    {
      operation: "getSnapshotTree",
      request: [versions[0]],
      responseBody: Buffer.from(JSON.stringify(snapshot)).toString("base64"),
      hash: createHash("sha256").update(JSON.stringify(snapshot)).digest("hex"),
      id: "tree",
      tree: {
        id: "tree",
        blobs: { data: "blob" },
        trees: {},
      },
    },
    {
      operation: "readBlob",
      id: "blob",
      byteLength: 3,
      hash: "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81",
      responseBody: "AQID",
    },
  ]);
});

test("review follow-up captures upstream connections and sends at the driver boundary", async (t) => {
  for (const method of ["createDocumentService", "createContainer"]) {
    await t.test(method, async () => {
      const sent = [];
      let clientId = "first-client";
      const service = {
        async connectToDeltaStream() {
          return { clientId, submit(messages) { sent.push(structuredClone(messages)); } };
        },
      };
      const transportEvidence = { connections: [], outboundOccurrences: [] };
      const factory = observedDocumentServiceFactory({
        async [method]() { return service; },
      }, [], { observeStorage: false, transportEvidence });
      const document = await factory[method]({ id: "document" });
      const connection = await document.connectToDeltaStream({ mode: "write" });
      assert.equal(transportEvidence.connections.length, 1,
        "Opening a driver connection was not captured before any submission");
      const first = structuredClone(transportEvidence.connections[0]);
      assert.equal(first.state, "opened");
      assert.equal(first.epoch, 1);
      assert.equal(first.clientId, "first-client");
      const messages = [{ type: "op", clientSequenceNumber: 1, contents: "original" }];
      connection.submit(messages);
      connection.clientId = "forged-client";
      connection.submit(messages);
      messages[0].contents = "mutated after submit";
      assert.equal(transportEvidence.connections.length, 1,
        "Changing a send's client ID created a connection");
      assert.deepEqual(transportEvidence.outboundOccurrences.map(
        ({ connectionId, submissions }) => ({
          connectionId, clientId: submissions[0].clientId,
          contents: submissions[0].messageBatches[0][0].contents,
        }),
      ), [1, 2].map(() => ({
        connectionId: first.connectionId, clientId: "first-client", contents: "original",
      })));
      clientId = "second-client";
      const retry = await document.connectToDeltaStream({ mode: "write" });
      retry.submit(sent[0]);
      const second = transportEvidence.connections[1];
      assert.equal(second.epoch, 2);
      assert.notEqual(second.connectionId, first.connectionId);
      assert.equal(second.clientId, "second-client");
      assert.equal(transportEvidence.outboundOccurrences[2].connectionId, second.connectionId);
      assert.deepEqual(sent, Array.from({ length: 3 }, () =>
        [{ type: "op", clientSequenceNumber: 1, contents: "original" }]));
    });
  }
});

test("review follow-up retains held upstream commits without inventing sends", {
  timeout: 60_000,
}, async () => {
  await withLocalFloodgate(async (config) => {
    const containers = [];
    try {
      const session = await openSession(config, containers);
      const adapter = upstreamAdapter(session);
      await adapter.set(["title"], "warmup");
      await adapter.awaitSynced();
      await adapter.checkpoint();
      await adapter.holdOutbound();
      const beforeEdit = session.transportEvidence().outboundOccurrences.length;
      await adapter.set(["title"], "held");
      const edit = await adapter.retainLastLocalCommit("edit");
      assert.deepEqual(edit.outboundRecords, []);
      assert.deepEqual(edit.transportObservations, []);
      assert.equal(session.transportEvidence().outboundOccurrences.length, beforeEdit);
      await adapter.releaseOutbound();
      await adapter.awaitSynced();
      await adapter.checkpoint();
      assert.equal(edit.outboundRecords.length, 1);
      assert.equal(edit.transportObservations.length, 1);
      await adapter.holdOutbound();
      const beforeUndo = session.transportEvidence().outboundOccurrences.length;
      const undo = await adapter.revert("edit", true);
      const retainedUndo = await adapter.retainLastLocalCommit("undo");
      await adapter.checkpoint();
      assert.equal(undo.authoredCount, 1);
      assert.equal(undo.outboundCount, 0);
      assert.deepEqual(undo.outboundRecords, []);
      assert.deepEqual(retainedUndo.transportObservations, []);
      assert.equal(session.transportEvidence().outboundOccurrences.length, beforeUndo);
      await adapter.releaseOutbound();
      await adapter.awaitSynced();
      await adapter.checkpoint();
      assert.equal(undo.outboundCount, 1);
      assert.equal(undo.transportObservations.length, 1);
      assert.equal(retainedUndo.transportObservations.length, 1);
      assert.equal(session.data.view.root.title, "warmup");
    } finally {
      cleanupOwned(containers);
    }
  });
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
