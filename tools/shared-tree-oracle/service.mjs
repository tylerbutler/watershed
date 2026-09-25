import assert from "node:assert/strict";
import { execFile, execFileSync, spawn } from "node:child_process";
import { createHash, createHmac, randomBytes, randomUUID } from "node:crypto";
import { once } from "node:events";
import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readFile, readdir, rename, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:net";
import { endianness } from "node:os";
import { dirname, join, resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { fileURLToPath, pathToFileURL } from "node:url";
import { parseArgs, promisify } from "node:util";
import { ConnectionState, LoaderHeader } from "@fluidframework/container-definitions/internal";
import {
  createDetachedContainer,
  loadExistingContainer,
} from "@fluidframework/container-loader/internal";
import { ContainerRuntime } from "@fluidframework/container-runtime/internal";
import { DriverHeader } from "@fluidframework/driver-definitions/internal";
import { SharedMap } from "@fluidframework/map/internal";
import { RouterliciousDocumentServiceFactory } from "@fluidframework/routerlicious-driver/internal";
import { makeCodeLoader, rootDataStoreId } from "@fluidframework/runtime-utils/internal";
import {
  defineDataStore,
  sharedObjectRegistryFromIterable,
} from "@fluidframework/shared-object-base/internal";
import { SharedTree } from "@fluidframework/tree/internal";
import { initialRoot, treeConfig } from "./schema.mjs";
import {
  reference, validateCapture, verifyCheckout, verifyPackages, verifyRepository,
} from "./source.mjs";

const directory = dirname(fileURLToPath(import.meta.url));
const repository = resolve(directory, "../..");
const execute = promisify(execFile);
export const floodgateRevision = "0eb493fc46d1bb9baf1151a6ccdde93544e057e7";
export const oldestSupportedClient = "2.117.0";
export const driverPolicies = {
  enableDiscovery: false,
  enableLongPollingDowngrade: false,
  enableRestLess: true,
  enableWholeSummaryUpload: false,
};
export const runtimeOptions = {
  enableRuntimeIdCompressor: "on",
  compressionOptions: {
    minimumBatchSizeInBytes: Infinity,
    compressionAlgorithm: "lz4",
  },
  summaryOptions: { summaryConfigOverrides: { state: "disabled" } },
};
export const summarizerRuntimeOptions = {
  ...runtimeOptions,
  summaryOptions: {
    summaryConfigOverrides: {
      state: "disableHeuristics",
      maxAckWaitTime: 15_000,
      maxOpsSinceLastSummary: 7000,
      initialSummarizerDelayMs: 0,
    },
  },
};

export const serviceStore = defineDataStore({
  type: "org.watershed.shared-tree.m1.bootstrap",
  registry: sharedObjectRegistryFromIterable([SharedMap, SharedTree]),
  async instantiateFirstTime(rootCreator, creator) {
    const bootstrap = await rootCreator.createSharedObject(SharedMap);
    const tree = await creator.createSharedObject(SharedTree);
    const view = tree.viewWith(treeConfig);
    view.initialize(initialRoot());
    view.dispose();
    bootstrap.set("tree", tree.handle);
    return bootstrap;
  },
  async view(bootstrap) {
    const handle = bootstrap.get("tree");
    assert.equal(typeof handle?.get, "function", "Bootstrap tree handle is missing");
    const tree = await handle.get();
    assert.equal(tree.attributes.type, SharedTree.getFactory().type, "Bootstrap handle is not a tree");
    return { bootstrap, tree, view: tree.viewWith(treeConfig) };
  },
});

export function serviceConfig(environment = process.env) {
  const secret = environment.FLOODGATE_JWT_SECRET;
  assert(secret?.length > 0, "FLOODGATE_JWT_SECRET is required");
  assert.equal(
    environment.FLOODGATE_REVISION, floodgateRevision,
    `FLOODGATE_REVISION must identify the pinned server: ${floodgateRevision}`,
  );
  function endpoint(value) {
    const url = new URL(value);
    assert(["http:", "https:"].includes(url.protocol), "Service endpoint must use HTTP or HTTPS");
    assert(!url.username && !url.password && !url.search && !url.hash, "Invalid service endpoint");
    return url.href.replace(/\/+$/, "");
  }
  const httpUrl = endpoint(environment.FLOODGATE_HTTP_URL ?? "http://127.0.0.1:3000");
  return {
    httpUrl,
    socketUrl: endpoint(environment.FLOODGATE_SOCKET_URL ?? httpUrl),
    tenantId: environment.FLOODGATE_TENANT_ID ?? "fluid",
    secret,
    revision: environment.FLOODGATE_REVISION,
  };
}

export function validatePreflight(result) {
  assert.equal(result.referenceVersion, reference.version, "Invalid referenceVersion");
  for (const field of [
    "transportVerified", "created", "peerObservedEdit", "summaryPublished", "deltaStorageVerified",
    "freshClientObservedEdit",
    "nativeJavaScriptTransportVerified", "nativeBeamTransportVerified",
  ]) {
    assert.equal(result[field], true, `Incomplete preflight: ${field}`);
  }
  assert.equal(result.mockService, false, "Preflight mockService must be false");
}

export function tokenProvider(config) {
  async function token(tenantId, documentId = "") {
    const now = Math.floor(Date.now() / 1000);
    const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
    const unsigned = `${encode({ alg: "HS256", typ: "JWT" })}.${encode({
      tenantId, documentId,
      scopes: ["doc:read", "doc:write", "summary:write"],
      user: { id: "shared-tree-oracle", name: "SharedTree Oracle" },
      ver: "1.0", jti: randomUUID(), iat: now, exp: now + 3600,
    })}`;
    const signature = createHmac("sha256", config.secret).update(unsigned).digest("base64url");
    return { jwt: `${unsigned}.${signature}` };
  }
  return { fetchOrdererToken: token, fetchStorageToken: token };
}

function urlResolver(config) {
  return {
    async resolve(request) {
      const id = new URL(request.url).pathname.split("/").filter(Boolean).at(-1);
      assert(id, "Document URL has no id");
      return {
        type: "fluid", id,
        url: `${config.httpUrl}/${config.tenantId}/${id}`,
        tokens: {},
        endpoints: {
          ordererUrl: config.httpUrl,
          // Attach replaces the final path segment with the server-assigned id.
          deltaStorageUrl: `${config.httpUrl}/deltas/${config.tenantId}/${id}`,
          deltaStreamUrl: config.socketUrl,
          storageUrl: `${config.httpUrl}/repos/${config.tenantId}`,
        },
      };
    },
    async getAbsoluteUrl(resolved, relative) {
      return relative ? `${resolved.url}/${relative.replace(/^\/+/, "")}` : resolved.url;
    },
  };
}

async function within(promise, stage, milliseconds = 30_000) {
  let timer;
  try {
    return await Promise.race([
      promise,
      new Promise((_resolve, reject) => {
        timer = setTimeout(() => reject(new Error(`Timed out: ${stage}`)), milliseconds);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

async function waitFor(predicate, stage, milliseconds = 15_000) {
  const deadline = Date.now() + milliseconds;
  while (!await predicate()) {
    if (Date.now() >= deadline) throw new Error(`Timed out: ${stage}`);
    await delay(25);
  }
}

export function cleanupOwned(resources, originalError) {
  const cleanupErrors = [];
  for (const resource of resources) {
    try {
      resource.dispose();
    } catch (error) {
      cleanupErrors.push(error);
    }
  }
  if (cleanupErrors.length === 0) return;
  if (originalError) {
    originalError.cleanupErrors = cleanupErrors;
    return;
  }
  throw new AggregateError(cleanupErrors, "Owned resource cleanup failed");
}

function observedResult(observations, operation, run) {
  return async (...args) => {
    try {
      return await run(...args);
    } catch (error) {
      observations.push({ operation, error: error.message });
      throw error;
    }
  };
}

function bind(target, property) {
  const value = target[property];
  return typeof value === "function" ? value.bind(target) : value;
}

function observedStorage(storage, observations) {
  return new Proxy(storage, {
    get(target, property) {
      if (property === "getVersions") {
        return observedResult(observations, "getVersions", async (...args) => {
          const result = await target.getVersions(...args);
          observations.push({
            operation: "getVersions",
            count: result.length,
            versions: result.map(({ id, treeId }) => ({ id, treeId })),
          });
          return result;
        });
      }
      if (property === "getSnapshotTree") {
        return observedResult(observations, "getSnapshotTree", async (...args) => {
          const result = await target.getSnapshotTree(...args);
          observations.push({
            operation: "getSnapshotTree",
            id: result?.id,
            blobs: Object.keys(result?.blobs ?? {}),
            trees: Object.keys(result?.trees ?? {}),
          });
          return result;
        });
      }
      if (property === "readBlob") {
        return observedResult(observations, "readBlob", async (id, ...args) => {
          const result = await target.readBlob(id, ...args);
          const bytes = Buffer.from(result);
          observations.push({
            operation: "readBlob",
            id,
            byteLength: bytes.length,
            hash: createHash("sha256").update(bytes).digest("hex"),
          });
          return result;
        });
      }
      return bind(target, property);
    },
  });
}

function observedDeltaStorage(storage, observations) {
  return new Proxy(storage, {
    get(target, property) {
      if (property !== "fetchMessages") return bind(target, property);
      return (...args) => {
        const [from, to] = args;
        const stream = target.fetchMessages(...args);
        observations.push({ operation: "fetchMessages", from, to: to ?? null });
        return new Proxy(stream, {
          get(streamTarget, streamProperty) {
            if (streamProperty !== "read") return bind(streamTarget, streamProperty);
            return observedResult(observations, "readMessages", async (...readArgs) => {
              const result = await streamTarget.read(...readArgs);
              observations.push({
                operation: "readMessages",
                done: result.done,
                sequenceNumbers: result.done
                  ? []
                  : result.value.map(({ sequenceNumber }) => sequenceNumber),
              });
              return result;
            });
          },
        });
      };
    },
  });
}

export function observedDocumentServiceFactory(
  factory,
  observations,
  { observeCreateContainer = false, observeStorage = true } = {},
) {
  return new Proxy(factory, {
    get(target, property) {
      if (property === "createContainer" && observeCreateContainer) {
        return observedResult(observations, "createContainer", async (summary, ...args) => {
          const service = await target.createContainer(summary, ...args);
          observations.push({
            operation: "createContainer",
            summary,
            documentId: service.resolvedUrl?.id ?? null,
          });
          return service;
        });
      }
      if (!observeStorage) return bind(target, property);
      if (property !== "createDocumentService") return bind(target, property);
      return observedResult(observations, "createDocumentService", async (resolved, ...args) => {
        const service = await target.createDocumentService(resolved, ...args);
        observations.push({
          operation: "createDocumentService",
          documentId: resolved?.id,
          result: "connected",
        });
        return new Proxy(service, {
          get(serviceTarget, serviceProperty) {
            if (serviceProperty === "connectToStorage") {
              return observedResult(observations, "connectToStorage", async (...storageArgs) => {
                const storage = await serviceTarget.connectToStorage(...storageArgs);
                observations.push({ operation: "connectToStorage", result: "connected" });
                return observedStorage(storage, observations);
              });
            }
            if (serviceProperty === "connectToDeltaStorage") {
              return observedResult(
                observations,
                "connectToDeltaStorage",
                async (...storageArgs) => {
                  const storage = await serviceTarget.connectToDeltaStorage(...storageArgs);
                  observations.push({
                    operation: "connectToDeltaStorage",
                    result: "connected",
                  });
                  return observedDeltaStorage(storage, observations);
                },
              );
            }
            return bind(serviceTarget, serviceProperty);
          },
        });
      });
    },
  });
}

export async function openSession(
  config,
  containers,
  documentId,
  summarizing = false,
  options = {},
) {
  const {
    cache = true,
    codeDetails = { package: "watershed-tree-oracle" },
    observeCreateContainer = false,
    observeStorage = false,
    store = serviceStore,
  } = options;
  assert(typeof cache === "boolean", "openSession cache must be a boolean");
  assert(typeof codeDetails?.package === "string", "openSession codeDetails must name a package");
  assert(typeof observeCreateContainer === "boolean",
    "openSession observeCreateContainer must be a boolean");
  assert(typeof observeStorage === "boolean", "openSession observeStorage must be a boolean");
  assert(typeof store?.type === "string", "openSession store must be a data store");
  let runtime;
  const storageObservations = [];
  const baseDocumentServiceFactory = new RouterliciousDocumentServiceFactory(
    tokenProvider(config), driverPolicies,
  );
  const documentServiceFactory = observeStorage || observeCreateContainer
    ? observedDocumentServiceFactory(baseDocumentServiceFactory, storageObservations, {
      observeCreateContainer,
      observeStorage,
    })
    : baseDocumentServiceFactory;
  const codeLoader = makeCodeLoader(
    async (type) => {
      assert.equal(type, store.type, "Unexpected data store type");
      return store;
    },
    oldestSupportedClient,
    async (parameters) => {
      const loaded = await ContainerRuntime.loadRuntime2({
        context: parameters.context,
        registry: parameters.registry,
        provideEntryPoint: parameters.provideEntryPoint,
        existing: parameters.existing,
        oldestSupportedClient: parameters.minVersionForCollab,
        runtimeOptions: summarizing ? summarizerRuntimeOptions : runtimeOptions,
      });
      runtime = loaded.runtime;
      if (!parameters.existing) {
        const store = await runtime.createDataStore(parameters.newContainerRootType);
        assert.equal(await store.trySetAlias(rootDataStoreId), "Success");
      }
      return runtime;
    },
    store,
  );
  const properties = {
    urlResolver: urlResolver(config),
    documentServiceFactory,
    codeLoader,
    configProvider: {
      getRawConfig: (name) => name === "Fluid.Container.ForceWriteConnection" ? true : undefined,
    },
  };
  const container = documentId === undefined
    ? await createDetachedContainer({ ...properties, codeDetails })
    : await loadExistingContainer({
      ...properties,
      request: {
        url: `${config.httpUrl}/${config.tenantId}/${documentId}`,
        headers: {
          ...(!cache || summarizing ? { [LoaderHeader.cache]: false } : {}),
          ...(summarizing ? {
            [LoaderHeader.clientDetails]: {
              capabilities: { interactive: false }, type: "summarizer",
            },
            [DriverHeader.summarizingClient]: true,
          } : {}),
        },
      },
    });
  containers.push(container);
  const data = await container.getEntryPoint();
  if (documentId === undefined) {
    await container.attach({ url: `${config.httpUrl}/${config.tenantId}/new` });
  }
  await waitFor(() => {
    assert(!container.closed, "Container closed before connecting");
    return container.connectionState === ConnectionState.Connected;
  }, "container connection");
  return {
    container,
    runtime,
    data,
    documentServiceFactory,
    storageObservations,
  };
}

export async function snapshot(storage) {
  const tree = await storage.getSnapshotTree();
  assert(tree, "Published snapshot is missing");
  const blobs = {};
  async function visit(node) {
    for (const id of Object.values(node.blobs)) {
      if (!(id in blobs)) {
        blobs[id] = Buffer.from(await storage.readBlob(id)).toString("base64");
      }
    }
    for (const child of Object.values(node.trees)) await visit(child);
  }
  await visit(tree);
  return { tree, blobs, blobEncoding: "base64" };
}

async function nativeTransports(config, documentId, summaryHandle) {
  for (const target of ["javascript", "erlang"]) {
    await execute("gleam", ["build", "--target", target], { cwd: repository, timeout: 120_000 });
  }
  const probe = await import(pathToFileURL(join(
    repository, "build/dev/javascript/watershed/watershed/shared_tree_transport_probe.mjs",
  )));
  const transport = await import(pathToFileURL(join(repository, "src/watershed/transport_ffi.mjs")));
  const { jwt } = await tokenProvider(config).fetchOrdererToken(config.tenantId, documentId);
  const topic = `document:${config.tenantId}:${documentId}`;
  const payload = JSON.stringify({
    tenantId: config.tenantId, id: documentId, token: jwt, mode: "read", versions: ["^0.4.0"],
    client: {
      mode: "read", permission: [], scopes: ["doc:read"],
      user: { id: "shared-tree-oracle" },
      details: { capabilities: { interactive: true }, environment: "watershed-m0-transport" },
    },
  });
  let channel;
  let javascript;
  try {
    javascript = await within(new Promise((resolve, reject) => {
      channel = transport.connect(
        config.socketUrl.replace(/^http/, "ws") + "/socket",
        topic, JSON.stringify({ token: jwt }),
        (event, text) => {
          if (event === "connect_document_success") {
            const observed = probe.observation(text, documentId, summaryHandle);
            if (observed.isOk()) resolve(JSON.parse(observed[0]));
            else reject(new Error(observed[0]));
          } else if (event === "connect_document_error" || event === "nack") {
            reject(new Error(`Native JavaScript transport received ${event}`));
          }
        },
        () => transport.push(channel, "connect_document", payload),
        () => reject(new Error("Native JavaScript transport closed before its handshake")),
      );
    }), "native JavaScript transport");
  } finally {
    if (channel !== undefined) transport.close(channel);
  }
  const erlang = join(repository, "build/dev/erlang");
  const libraries = (await readdir(erlang, { withFileTypes: true }))
    .filter((entry) => entry.isDirectory())
    .map((entry) => join(erlang, entry.name, "ebin"));
  const endpoint = new URL(config.socketUrl);
  assert.equal(endpoint.protocol, "http:", "The native BEAM preflight requires the selected local HTTP profile");
  const { stdout } = await execute("erl", [
    "-noshell", "-pa", ...libraries,
    "-eval", "{ok, _} = application:ensure_all_started(watershed), 'watershed@shared_tree_transport_probe':main(), init:stop().",
  ], {
    cwd: repository, timeout: 20_000,
    env: {
      ...process.env,
      WATERSHED_TREE_HOST: endpoint.hostname,
      WATERSHED_TREE_PORT: endpoint.port || "80",
      WATERSHED_TREE_TOPIC: topic,
      WATERSHED_TREE_TOKEN: jwt,
      WATERSHED_TREE_CONNECT: payload,
      WATERSHED_TREE_DOCUMENT: documentId,
      WATERSHED_TREE_SUMMARY: summaryHandle,
      ERL_CRASH_DUMP: join(directory, ".output/transport-erl-crash.dump"),
    },
  });
  const marker = "WATERSHED_TREE_TRANSPORT=";
  const results = stdout.split("\n").filter((line) => line.startsWith(marker));
  assert.equal(results.length, 1, "Native BEAM transport did not report exactly one observation");
  return { javascript, erlang: JSON.parse(results[0].slice(marker.length)) };
}

export async function preflight(config) {
  const containers = [];
  let stage = "health";
  let scenarioError;
  try {
    const health = await fetch(`${config.httpUrl}/health`, { signal: AbortSignal.timeout(5000) });
    assert.equal(health.status, 200, `health returned ${health.status}`);
    await health.text();
    stage = "reference verification";
    await verifyPackages();
    await verifyCheckout();
    const source = JSON.parse(await readFile(join(directory, ".output/source/source-smoke.json"), "utf8"));
    validateCapture(source);
    assert.equal(source.minVersionForCollab, oldestSupportedClient);

    stage = "create and attach";
    const first = await within(openSession(config, containers), stage);
    const id = first.container.resolvedUrl.id;
    stage = "peer load";
    const second = await within(openSession(config, containers, id), stage);
    stage = "peer edit delivery";
    first.data.view.root.title = "real-service";
    second.data.view.root.point.x = 7;
    await waitFor(() => {
      assert(!first.container.closed && !second.container.closed, "Container closed during edits");
      return first.data.view.root.point.x === 7
        && second.data.view.root.title === "real-service"
        && !first.container.isDirty && !second.container.isDirty;
    }, stage);

    stage = "summary client load";
    const summaryClient = await within(openSession(config, containers, id, true), stage);
    assert(summaryClient.data.ISummarizer, "Summary client entry point has no ISummarizer");
    stage = "summary publication";
    const summary = summaryClient.data.ISummarizer.summarizeOnDemand({
      reason: "SharedTree preflight", fullTree: true,
    });
    const submitted = await within(summary.summarySubmitted, "summary submission");
    assert(submitted.success, `Summary submission failed: ${submitted.error?.message ?? submitted.error}`);
    assert.equal(submitted.data.stage, "submit");
    const broadcast = await within(summary.summaryOpBroadcasted, "summary broadcast");
    assert(broadcast.success, `Summary broadcast failed: ${broadcast.error?.message ?? broadcast.error}`);
    const acknowledged = await within(summary.receivedSummaryAckOrNack, "summary acknowledgement");
    assert(acknowledged.success, `Summary acknowledgement failed: ${acknowledged.error?.message ?? acknowledged.error}`);
    const version = acknowledged.data.summaryAckOp.contents.handle;
    assert.equal(typeof version, "string");
    assert(version.length > 0);

    stage = "published storage";
    const service = await first.documentServiceFactory.createDocumentService(first.container.resolvedUrl);
    let stored;
    const history = [];
    try {
      const storage = await service.connectToStorage();
      const versions = await storage.getVersions(null, 1);
      assert.equal(versions[0]?.id, version, "Summary ack does not identify the published head");
      stored = await snapshot(storage);
      stage = "delta storage";
      const deltaStorage = await service.connectToDeltaStorage();
      const end = acknowledged.data.summaryAckOp.sequenceNumber + 1;
      const stream = deltaStorage.fetchMessages(1, end, AbortSignal.timeout(15_000), false);
      for (;;) {
        const chunk = await within(stream.read(), "delta storage");
        if (chunk.done) break;
        history.push(...chunk.value);
      }
      assert.equal(history.length, end - 1, "Delta storage omitted sequenced messages");
      assert(history.every((message, index) => message.sequenceNumber === index + 1),
        "Delta storage reordered or duplicated messages");
    } finally {
      service.dispose();
    }

    stage = "summary format inventory";
    const rootBlob = (name) => JSON.parse(Buffer.from(
      stored.blobs[stored.tree.blobs[name]], "base64",
    ).toString("utf8"));
    const metadata = rootBlob(".metadata");
    assert.equal(metadata.documentSchema.info.minVersionForCollab, oldestSupportedClient);
    assert.equal(metadata.sweepEnabled, false, "The selected profile must not enable GC sweep");
    assert.notEqual(metadata.documentSchema.runtime.compressionLz4, true);
    assert.equal(metadata.documentSchema.runtime.opGroupingEnabled, true);
    const compressorBytes = Uint8Array.from(Buffer.from(rootBlob(".idCompressor"), "base64"));
    const compressorVersion = new Float64Array(compressorBytes.buffer)[0];
    assert.equal(compressorVersion, source.compressorFormat.version);
    const summaryPaths = [];
    function paths(tree, prefix = "") {
      for (const name of Object.keys(tree.blobs)) summaryPaths.push(`${prefix}/${name}`);
      for (const [name, child] of Object.entries(tree.trees)) paths(child, `${prefix}/${name}`);
    }
    paths(stored.tree);

    stage = "fresh client reload";
    summaryClient.container.dispose();
    first.container.dispose();
    second.container.dispose();
    const fresh = await within(openSession(config, containers, id), stage);
    assert.equal(fresh.data.view.root.title, "real-service");
    assert.equal(fresh.data.view.root.point.x, 7);
    fresh.data.view.root.enabled = true;
    await waitFor(() => {
      assert(!fresh.container.closed, "Reloaded container closed while editing");
      return !fresh.container.isDirty;
    }, "fresh client edit acknowledgement");

    stage = "native transport verification";
    const nativeTransport = await nativeTransports(config, id, version);
    const result = {
      referenceVersion: reference.version, transportVerified: true, created: true,
      peerObservedEdit: true, summaryPublished: true, freshClientObservedEdit: true,
      mockService: false,
      deltaStorageVerified: true,
      nativeJavaScriptTransportVerified: true, nativeBeamTransportVerified: true,
    };
    validatePreflight(result);
    return {
      result,
      profile: {
        formatVersion: 1,
        reference: { package: "@fluidframework/tree", version: reference.version, commit: reference.commit },
        service: {
          implementation: "floodgate", revision: config.revision, transport: "socket.io", driverPolicies,
          deltaStorageRoute: "/deltas/{tenantId}/{documentId}",
          nativeTransport: {
            protocol: "phoenix", endpoint: "/socket/websocket",
            javascript: "watershed/transport_js", erlang: "aquamarine/phoenix",
          },
        },
        container: {
          runtimeOptions, summarizerRuntimeOptions, oldestSupportedClient,
          documentSchema: metadata.documentSchema,
          summaryFormatVersion: metadata.summaryFormatVersion,
          gcFeature: metadata.gcFeature,
          summaryPaths,
          bootstrapPath: fresh.data.bootstrap.handle.absolutePath,
          treePath: fresh.data.tree.handle.absolutePath,
          channelAttributes: { bootstrap: fresh.data.bootstrap.attributes, tree: fresh.data.tree.attributes },
          dataStoreTypes: [serviceStore.type],
          bootstrapChannelTypes: [fresh.data.bootstrap.attributes.type],
        },
        codecTree: source.codecTree,
        compressorFormat: { version: compressorVersion, byteOrder: endianness() },
        supportedFeatures: [
          "fixed-object-schema", "primitive-leaves", "optional-string", "nested-object",
          "bootstrap-map-handle", "grouped-batches", "gc-metadata",
        ],
        excludedFeatures: ["arrays", "maps-in-tree", "schema-evolution", "shared-branches", "gc-sweep", "compressed-ops", "chunked-ops"],
      },
      capture: {
        documentId: id,
        summaryVersion: version,
        summaryReferenceSequenceNumber: submitted.data.referenceSequenceNumber,
        summaryAcknowledgement: acknowledged.data.summaryAckOp,
        summaryTree: submitted.data.summaryTree,
        snapshot: stored,
        history,
        nativeTransport,
        bootstrapPath: fresh.data.bootstrap.handle.absolutePath,
        treePath: fresh.data.tree.handle.absolutePath,
        observations: { title: fresh.data.view.root.title, pointX: fresh.data.view.root.point.x },
      },
    };
  } catch (error) {
    const status = error.statusCode === undefined ? "" : ` (HTTP ${error.statusCode})`;
    scenarioError = new Error(
      `SharedTree preflight failed at ${stage}${status}: ${error.message}`,
      { cause: error },
    );
    throw scenarioError;
  } finally {
    cleanupOwned(containers, scenarioError);
  }
}

export async function localFloodgateReady(
  child,
  httpUrl,
  { fetch: request = fetch } = {},
) {
  assert(child.exitCode === null && child.signalCode === null,
    "Floodgate exited before becoming ready");
  try {
    const response = await request(`${httpUrl}/health`, {
      signal: AbortSignal.timeout(1000),
    });
    await response.text();
    assert.equal(response.status, 200, "Floodgate health is not ready");
    return true;
  } catch (error) {
    if (error instanceof TypeError) return false;
    throw error;
  }
}

export async function withLocalFloodgate(run) {
  const checkout = join(directory, ".reference/floodgate");
  if (!existsSync(checkout)) {
    await mkdir(dirname(checkout), { recursive: true });
    execFileSync("git", [
      "clone", "--quiet", "--filter=blob:none", "--no-checkout",
      "https://github.com/tylerbutler/floodgate.git", checkout,
    ], { stdio: "inherit" });
    execFileSync("git", ["-C", checkout, "checkout", "--quiet", "--detach", floodgateRevision]);
  }
  await verifyRepository(checkout, floodgateRevision);
  execFileSync("gleam", ["export", "erlang-shipment"], {
    cwd: checkout, stdio: "inherit",
    env: {
      ...process.env,
      GIT_CONFIG_COUNT: "1", GIT_CONFIG_KEY_0: "safe.bareRepository", GIT_CONFIG_VALUE_0: "all",
    },
  });
  await verifyRepository(checkout, floodgateRevision);
  const reservation = createServer();
  reservation.listen(0, "127.0.0.1");
  await once(reservation, "listening");
  const port = reservation.address().port;
  await new Promise((resolve) => reservation.close(resolve));
  await mkdir(join(directory, ".output"), { recursive: true });
  const data = await mkdtemp(join(directory, ".output/floodgate-"));
  const secret = randomBytes(32).toString("hex");
  const httpUrl = `http://127.0.0.1:${port}`;
  const child = spawn("sh", ["build/erlang-shipment/entrypoint.sh", "run"], {
    cwd: checkout, stdio: ["ignore", "inherit", "inherit"],
    env: {
      ...process.env, PORT: String(port), FLOODGATE_BIND: "127.0.0.1",
      FLOODGATE_PUBLIC_URL: httpUrl, FLOODGATE_TENANT_ID: "fluid",
      FLOODGATE_JWT_SECRET: secret, FLOODGATE_STORAGE_BACKEND: "shelf", FLOODGATE_DATA_DIR: data,
    },
  });
  let startupError;
  child.on("error", (error) => { startupError = error; });
  const exited = new Promise((resolve) => child.once("exit", resolve));
  try {
    await waitFor(async () => {
      if (startupError) throw startupError;
      return localFloodgateReady(child, httpUrl);
    }, "local Floodgate startup");
    return await run(serviceConfig({
      FLOODGATE_HTTP_URL: httpUrl, FLOODGATE_JWT_SECRET: secret, FLOODGATE_REVISION: floodgateRevision,
    }));
  } finally {
    if (child.pid !== undefined && child.exitCode === null && child.signalCode === null) {
      child.kill("SIGTERM");
      await within(exited, "local Floodgate shutdown", 10_000);
    }
    await rm(data, { recursive: true, force: true });
  }
}

function json(value) {
  return `${JSON.stringify(value, (_key, item) => {
    if (item === Infinity) return "Infinity";
    if (item instanceof Uint8Array) return { encoding: "base64", content: Buffer.from(item).toString("base64") };
    return item;
  }, 2)}\n`;
}

async function runPreflightCommand(args) {
  const { values, positionals } = parseArgs({
    args,
    allowPositionals: true,
    options: {
      local: { type: "boolean", default: false },
      service: { type: "string", default: "floodgate" },
      output: { type: "string", default: join(directory, ".output/service") },
    },
  });
  assert.deepEqual(positionals, ["preflight"], "Usage: service.mjs preflight [--local] [--output path]");
  assert.equal(values.service, "floodgate", "Only the pinned Floodgate service is supported");
  const captured = values.local
    ? await withLocalFloodgate(preflight)
    : await preflight(serviceConfig());
  const output = resolve(values.output);
  await mkdir(output, { recursive: true });
  const temporary = await mkdtemp(join(output, ".preflight-"));
  try {
    for (const [name, value] of Object.entries(captured)) {
      await writeFile(join(temporary, `${name}.json`), json(value));
    }
    for (const name of ["capture", "profile", "result"]) {
      await rename(join(temporary, `${name}.json`), join(output, `${name}.json`));
    }
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
  console.log(json(captured.result));
}

export async function runServiceCommand(args, {
  importInterop = () => import("./interop.mjs"),
  runPreflight = runPreflightCommand,
} = {}) {
  const [command, ...rest] = args;
  if (command === "interop") {
    const { runInteropCommand } = await importInterop();
    return runInteropCommand(rest);
  }
  return runPreflight(args);
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  runServiceCommand(process.argv.slice(2)).catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
