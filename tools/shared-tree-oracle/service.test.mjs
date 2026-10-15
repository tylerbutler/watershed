import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { once } from "node:events";
import { readFile, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import test from "node:test";
import { SchemaFactory, TreeViewConfiguration } from "fluid-framework/alpha";
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
  arrayServiceStore,
  branchExcludedFeatures,
  branchSupportedFeatures,
  mapServiceStore,
  handleGraphStore,
  handleServiceStore,
  lifecycleProfile,
  excludedFeatures,
  serviceConfig,
  serviceStore,
  supportedFeatures,
  tokenProvider,
  runServiceCommand,
  validatePreflight,
  withLocalFloodgate,
} from "./service.mjs";
import {
  HandleLinks,
  HandleRoot,
  HandleSequence,
  handleStoredSchema,
  handleTreeConfig,
  initialHandleRoot,
} from "./schema.mjs";
import {
  assertPreflightProfile,
  validateLocalBranchRow,
  validateLocalBranchSections,
} from "./interop.mjs";
import {
  nativeAdapter,
  publishUpstreamSummary,
  runLocalBranchConcurrentCell,
  runLocalBranchLifetimeCell,
  runLocalBranchReconnectCell,
  runLocalBranchScenarios,
  upstreamAdapter,
  success,
  until,
} from "./interop-scenarios.mjs";
import { runLocalBranchReloadMatrix } from "./summary-interop.mjs";

test("service profile names supported M5 behavior and its limits", () => {
  for (const feature of [
    "strict-view-object-map-schema-evolution",
    "identifier-summary-reload",
    "synchronous-single-tree-transactions",
    "stable-node-existence-constraints",
    "application-owned-revertibles",
    "default-undo-redo-commit-kinds",
    "runtime-local-handle-lifetime",
    "reconnect-with-live-handles",
    "object-map-array-move-transaction-undo-redo",
    "sequenced-commit-outcomes",
  ]) {
    assert(supportedFeatures.includes(feature), `Missing support: ${feature}`);
  }
  assert(!excludedFeatures.includes("schema-evolution"));
  assert(!excludedFeatures.includes("public-transactions"));
  assert(!excludedFeatures.includes("undo-redo"));
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
    "persisted-undo-redo-stacks",
    "schema-undo",
    "remote-commit-undo",
    "undo-during-transactions",
    "cross-tree-atomic-undo",
    "custom-revert-metadata",
    "clone-to-view",
    "revert-to",
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

test("service profile publishes the accepted handle lifecycle boundary", {
  timeout: 180_000,
}, async () => {
  assert.deepEqual(lifecycleProfile, {
    nativeTargets: ["javascript", "erlang"],
    seed: 42,
    iterations: 300,
    reloadCells: 27,
    targetKinds: ["SharedMap", "SharedTree"],
    datastoreType: "org.watershed.shared-tree.m7.graph",
    cases: [
      "handle-leaves",
      "live-channel-attachment",
      "cross-datastore-attachment",
      "handle-transaction-branch",
      "handle-retention",
    ],
    requiredSections: [
      "handleValues",
      "channelAttachment",
      "datastoreAttachment",
      "handleTransactionBranch",
      "handleRetention",
      "handleReconnect",
      "handleReloadMatrix",
    ],
  });
  for (const feature of [
    "handle-valued-tree-leaves",
    "detached-shared-map-and-tree-creation",
    "implicit-attachment-graphs",
    "declared-cross-datastore-references",
    "retained-handle-routes",
    "new-alias-authoring",
    "declared-initial-container-layouts",
  ]) {
    assert(supportedFeatures.includes(feature), `Missing support: ${feature}`);
  }
  for (const feature of [
    "blob-handles",
    "arbitrary-datastore-factories",
    "cross-container-handles",
    "production-authentication",
    "pending-state-disk-recovery",
    "richer-typed-handle-consumers",
  ]) {
    assert(excludedFeatures.includes(feature), `Missing exclusion: ${feature}`);
  }
  await withLocalFloodgate(async (config) => {
    const captured = await preflight(config);
    const committed = JSON.parse(await readFile(new URL(
      "../../test/fixtures/shared_tree/profile.json",
      import.meta.url,
    ), "utf8"));
    assertPreflightProfile(captured.profile, committed);
  });
});

test("handle schema and exact primary and secondary stores are exported", () => {
  assert.equal(typeof HandleRoot, "function");
  assert.equal(typeof HandleLinks, "function");
  assert.equal(typeof HandleSequence, "function");
  assert(handleTreeConfig);
  assert(initialHandleRoot() instanceof HandleRoot);
  assert.deepEqual(handleStoredSchema.root, {
    kind: "Value",
    types: ["org.watershed.shared-tree.handles.Root"],
  });
  assert.equal(handleServiceStore.type, "org.watershed.shared-tree.m1.bootstrap");
  assert.equal(handleGraphStore.type, "org.watershed.shared-tree.m7.graph");
});

test("native named objects publish actual graphs and preserve the default tree", {
  timeout: 180_000,
}, async () => {
  const stringSchema = {
    version: 2,
    nodes: { "com.fluidframework.leaf.string": { kind: { leaf: 1 } } },
    root: { kind: "Value", types: ["com.fluidframework.leaf.string"] },
  };
  const optionalStringSchema = {
    ...stringSchema,
    root: { kind: "Optional", types: ["com.fluidframework.leaf.string"] },
  };
  await withLocalFloodgate(async (config) => {
    for (const target of ["javascript", "erlang"]) {
      const containers = [];
      let native;
      try {
        const options = { store: handleServiceStore };
        const creator = await openSession(config, containers, undefined, false, options);
        const documentId = creator.container.resolvedUrl.id;
        await publishUpstreamSummary(config, containers, documentId, "named object bootstrap", options);
        const peer = await openSession(config, containers, documentId, false, options);
        const jwt = (await tokenProvider(config).fetchOrdererToken(config.tenantId, documentId)).jwt;
        native = await nativeAdapter(target, config, {
          runId: `named-objects-${target}`,
          documentId,
          tenant: config.tenantId,
          viewSchema: JSON.stringify(handleStoredSchema),
          viewSchemas: {
            default: JSON.stringify(handleStoredSchema),
            "required-string": JSON.stringify(stringSchema),
          },
        }, jwt);
        const command = async (request) => success(
          await native.client.request(request), `${target} ${request.command}`,
        ).result;
        const matchesBranch = (label, branch, tree) =>
          tree === undefined
            ? label === branch
            : label === `${tree}:${branch}`
              || (target === "erlang" && label === branch);
        const branchCommits = async (
          branch, tree, expectedTypes = ["commit"],
        ) => {
          const commits = [];
          try {
            await until(async () => {
              commits.push(...(await native.client.checkpoint(tree)).commits);
              const owned = commits.filter(({ branch: label }) =>
                matchesBranch(label, branch, tree)
              );
              return expectedTypes.every((type) =>
                owned.some(({ type: observed }) => observed === type)
              );
            }, `${tree ?? "main"}:${branch} commit settlement`);
          } catch (error) {
            throw new Error(`${error.message}: ${JSON.stringify(commits)}`, {
              cause: error,
            });
          }
          return commits.filter(({ branch: label }) =>
            matchesBranch(label, branch, tree)
          );
        };
        const owningTreeCommits = async (branch, tree) => {
          const commits = [];
          await until(async () => {
            commits.push(...(await native.client.checkpoint(tree)).commits);
            const hasBranchCommit = commits.some(({ type, branch: label }) =>
              type === "commit"
                && matchesBranch(label, branch, tree)
            );
            const hasSettlement = commits.some(({ type, tree: ownerTree }) =>
              type === "settlement" && ownerTree === tree
            );
            return hasBranchCommit && hasSettlement;
          }, `${tree ?? "main"}:${branch} owning-tree commits`);
          return commits;
        };
        await native.awaitSynced();
        await command({ command: "root-map", name: "bootstrap" });
        await command({ command: "create-data-store", name: "secondary" });
        const entry = await command({
          command: "data-store-root", store: "secondary", name: "entry",
        });
        const map = await command({
          command: "create-map", store: "secondary", name: "map",
        });
        const tree = await command({
          command: "create-tree",
          store: "secondary",
          name: "draft",
          schema: optionalStringSchema,
          view: optionalStringSchema,
          initialRoot: { kind: "string", value: "start" },
        });
        for (const marker of [entry, map, tree]) {
          assert.equal(marker.type, "__fluid_handle__");
          assert.match(marker.url, /^\/[^/]+\/[^/]+$/);
        }
        await command({ command: "shared-map-set", name: "map", key: "value", value: "before" });
        await command({ command: "shared-map-set", name: "entry", key: "map", value: map });
        await command({ command: "shared-map-set", name: "entry", key: "tree", value: tree });
        assert.equal(peer.data.bootstrap.has("secondary"), false);
        await command({
          command: "shared-map-set", name: "bootstrap", key: "secondary", value: entry,
        });
        await native.awaitSynced();
        await until(() => peer.data.bootstrap.has("secondary"), "secondary graph publication");
        const loadedEntry = await peer.data.bootstrap.get("secondary").get();
        const loadedMap = await loadedEntry.get("map").get();
        assert.equal(loadedMap.get("value"), "before");
        const loadedTree = await loadedEntry.get("tree").get();
        const namedFactory = new SchemaFactory("org.watershed.shared-tree.named");
        const view = loadedTree.viewWith(new TreeViewConfiguration({
          schema: namedFactory.optional(namedFactory.string),
        }));
        containers.push({ dispose: () => view.dispose() });
        assert.equal(view.root, "start");

        const malformedBefore = await native.client.sharedMapGet("map", "value");
        const pendingBefore = (await native.client.request({
          command: "shared-map-get", name: "map", key: "value",
        })).observation.pendingTreeCount;
        const outboundBefore = native.client.gate.evidence();
        const outboundOpCount = (evidence) =>
          [...evidence.held, ...evidence.delivered]
            .filter(({ direction, kind }) => direction === "outbound" && kind === "op")
            .length;
        const malformed = await native.client.request({
          command: "shared-map-set",
          name: "map",
          key: "value",
          value: { type: "__fluid_handle__", url: 123 },
        });
        assert.equal(malformed.ok, false);
        assert.equal(malformed.error.code, "facade-error");
        assert.equal(malformed.observation.pendingTreeCount, pendingBefore);
        assert.equal(
          outboundOpCount(native.client.gate.evidence()),
          outboundOpCount(outboundBefore),
        );
        assert.deepEqual(await native.client.sharedMapGet("map", "value"), malformedBefore);
        assert.equal(loadedMap.get("value"), "before");

        await native.client.subscribe("draft");
        await command({
          command: "set", path: ["label"],
          value: { kind: "string", value: "main-first" },
        });
        await command({
          command: "set", tree: "draft", path: [],
          value: { kind: "string", value: "selected-first" },
        });
        const selectedFirst = await native.client.checkpoint("draft");
        const mainFirst = await native.client.checkpoint();
        assert.deepEqual(selectedFirst.events.map(({ kind }) => kind), ["data"]);
        assert.deepEqual(mainFirst.events.map(({ kind }) => kind), ["data"]);

        await command({
          command: "set", tree: "draft", path: [],
          value: { kind: "string", value: "selected-second" },
        });
        await command({
          command: "set", path: ["label"],
          value: { kind: "string", value: "main-second" },
        });
        const mainSecond = await native.client.checkpoint();
        const selectedSecond = await native.client.checkpoint("draft");
        assert.deepEqual(mainSecond.events.map(({ kind }) => kind), ["data"]);
        assert.deepEqual(selectedSecond.events.map(({ kind }) => kind), ["data"]);

        await native.client.unsubscribe("draft");
        await command({
          command: "set", tree: "draft", path: [],
          value: { kind: "string", value: "selected-third" },
        });
        await command({
          command: "set", path: ["label"],
          value: { kind: "string", value: "main-third" },
        });
        assert.deepEqual((await native.client.checkpoint("draft")).events, []);
        assert.deepEqual(
          (await native.client.checkpoint()).events.map(({ kind }) => kind),
          ["data"],
        );

        await native.client.checkpoint();
        await native.client.checkpoint("draft");
        await native.client.fork("main", "checkpoint-default");
        await native.client.fork("main", "checkpoint-named", "draft");
        await native.client.branchEdit("checkpoint-default", {
          kind: "object-set", path: ["label"], value: "default-branch-commit",
        });
        await native.client.branchEdit("checkpoint-named", {
          kind: "object-set", path: [], value: "named-branch-commit",
        }, "draft");
        const retainedDefaultCheckpoint = await native.client.retainLastLocalCommit(
          "checkpoint-default-edit", "checkpoint-default",
        );
        const retainedNamedCheckpoint = await native.client.retainLastLocalCommit(
          "checkpoint-named-edit", "checkpoint-named", "draft",
        );
        assert.equal(retainedDefaultCheckpoint.factoryAvailable, true);
        assert.equal(retainedNamedCheckpoint.factoryAvailable, true);
        await native.client.mergeBranch(
          "main", "checkpoint-named", true, "draft",
        );
        await native.awaitSynced();
        const namedBranchCommits = await owningTreeCommits(
          "checkpoint-named", "draft",
        );
        assert.equal(
          namedBranchCommits.some(({ type, factoryAvailable, tree }) =>
            type === "commit" && factoryAvailable === true && tree === "draft"
          ),
          true,
        );
        assert.equal(
          namedBranchCommits.some(({ type, tree: ownerTree }) =>
            type === "settlement" && ownerTree === "draft"
          ),
          true,
        );
        await native.client.mergeBranch("main", "checkpoint-default", true);
        await native.awaitSynced();
        const defaultBranchCommits = await owningTreeCommits(
          "checkpoint-default", undefined,
        );
        assert.equal(
          defaultBranchCommits.some(({ type, factoryAvailable, tree }) =>
            type === "commit" && factoryAvailable === true && tree === undefined
          ),
          true,
        );
        assert.equal(
          defaultBranchCommits.some(({ type, tree: ownerTree }) =>
            type === "settlement" && ownerTree === undefined
          ),
          true,
        );
        assert.equal(
          defaultBranchCommits.some(({ tree }) => tree === "draft"),
          false,
        );

        const explicitDefaultMain = await native.client.branchEdit("main", {
          kind: "object-set", path: ["label"], value: "explicit-default-main",
        });
        assert.equal(explicitDefaultMain.authoredCount, 1);
        assert.equal(explicitDefaultMain.outboundCount, 1);
        const retainedExplicitDefault = await native.client.retainLastLocalCommit(
          "explicit-default-main", "main",
        );
        assert.equal(retainedExplicitDefault.factoryAvailable, true);
        const explicitNamedMain = await native.client.branchEdit("main", {
          kind: "object-set", path: [], value: "explicit-named-main",
        }, "draft");
        assert.equal(explicitNamedMain.authoredCount, 1);
        assert.equal(explicitNamedMain.outboundCount, 1);
        const retainedExplicitNamed = await native.client.retainLastLocalCommit(
          "explicit-named-main", "main", "draft",
        );
        assert.equal(retainedExplicitNamed.factoryAvailable, true);
        await native.awaitSynced();
        await until(
          () => peer.data.view.root.label === "explicit-default-main",
          "explicit default main publication",
        );
        await until(() => view.root === "explicit-named-main", "explicit named main publication");
        assert.deepEqual(await native.client.read(["label"]), {
          present: true,
          value: { kind: "string", value: "explicit-default-main" },
        });
        await native.client.disposeRevertible("explicit-default-main");
        await native.client.disposeRevertible("explicit-named-main");

        await command({
          command: "set", tree: "draft", path: [],
          value: { kind: "string", value: "undo-target" },
        });
        await native.client.fork("main", "draft");
        const defaultDraftEdit = await native.client.branchEdit("draft", {
          kind: "object-set", path: ["label"], value: "default-draft",
        });
        assert.equal(defaultDraftEdit.outboundCount, 0);
        const retainedSelected = await command({
          op: "retainLastLocalCommit", tree: "draft", name: "selected-edit",
        });
        const retainedDefaultBranch = await command({
          op: "retainLastLocalCommit",
          branch: "draft",
          name: "default-draft-edit",
        });
        assert.equal(typeof retainedSelected.revision, "string");
        assert.equal(retainedDefaultBranch.factoryAvailable, true);
        await native.client.disposeRevertible("default-draft-edit");
        await native.client.disposeBranch("draft");
        await native.awaitSynced();
        await until(() => view.root === "undo-target", "named tree retained edit");
        const undo = await command({
          op: "revert", tree: "draft", name: "selected-edit", dispose: true,
        });
        assert.equal(undo.authoredKind, "Undo");
        assert.equal(undo.outboundCount, 1);
        assert.equal(undo.submittedRevisions.length, 1);
        await native.awaitSynced();
        await until(
          () => view.root === "explicit-named-main",
          "named tree undo",
        );

        const namedHandles = {};
        for (const name of ["a", "a:b"]) {
          namedHandles[name] = await command({
            command: "create-tree",
            store: "secondary",
            name,
            schema: stringSchema,
            view: stringSchema,
            initialRoot: { kind: "string", value: name },
          });
          await command({
            command: "shared-map-set", name: "entry", key: `tree-${name}`,
            value: namedHandles[name],
          });
        }
        await native.client.fork("main", "b:c", "a");
        await native.client.fork("main", "c", "a:b");
        await native.client.fork("main", "a:b:c");
        await native.client.branchEdit("b:c", {
          kind: "object-set", path: [], value: "branch-a",
        }, "a");
        await native.client.branchEdit("c", {
          kind: "object-set", path: [], value: "branch-ab",
        }, "a:b");
        await native.client.branchEdit("a:b:c", {
          kind: "object-set", path: ["label"], value: "branch-main",
        });
        await native.client.mergeBranch("main", "b:c", true, "a");
        await native.client.mergeBranch("main", "c", true, "a:b");
        await native.client.mergeBranch("main", "a:b:c", true);
        assert.deepEqual(await native.client.read([], "a"), {
          present: true, value: { kind: "string", value: "branch-a" },
        });
        assert.deepEqual(await native.client.read([], "a:b"), {
          present: true, value: { kind: "string", value: "branch-ab" },
        });
        assert.deepEqual(await native.client.read(["label"]), {
          present: true, value: { kind: "string", value: "branch-main" },
        });
        const unknownBranch = await native.client.request({
          op: "branchEdit", tree: "a", branch: "c",
          edit: { kind: "object-set", path: [], value: "wrong" },
        });
        assert.equal(unknownBranch.ok, false);

        await native.awaitSynced();
        const beforeForkResources = await command({
          command: "runtime-state-evidence",
        });
        await native.client.fork("main", "draft", "draft");
        assert.notEqual(
          await command({ command: "runtime-state-evidence" }),
          beforeForkResources,
          `${target} actual fork was absent from runtime state evidence`,
        );
        const preservedDraftEdit = await native.client.branchEdit("draft", {
          kind: "object-set", path: [], value: "preserved-draft",
        }, "draft");
        assert.equal(preservedDraftEdit.outboundCount, 0);
        const retainedBeforeDuplicate = await native.client.retainLastLocalCommit(
          "duplicate-before", "draft", "draft",
        );
        assert.equal(retainedBeforeDuplicate.factoryAvailable, true);
        const beforeDuplicateCommits = await branchCommits(
          "draft", "draft", ["commit"],
        );
        assert.equal(
          beforeDuplicateCommits.filter(({ type }) => type === "commit").length,
          1,
        );
        await native.awaitSynced();
        const beforeDuplicateResources = await command({
          command: "runtime-state-evidence",
        });
        assert.match(beforeDuplicateResources, /^[a-f0-9]{64}$/);
        const duplicateFork = await native.client.request({
          op: "fork", tree: "draft", source: "main", name: "draft",
        });
        assert.equal(duplicateFork.ok, false);
        assert.equal(
          await command({ command: "runtime-state-evidence" }),
          beforeDuplicateResources,
          `${target} duplicate fork changed runtime checkout, subscription or retention state`,
        );
        assert.equal(
          (await native.client.revertibleStatus("duplicate-before")).status,
          "Valid",
        );
        const afterDuplicateEdit = await native.client.branchEdit("draft", {
          kind: "object-set", path: [], value: "preserved-after-duplicate",
        }, "draft");
        assert.equal(afterDuplicateEdit.authoredCount, 1);
        assert.equal(afterDuplicateEdit.outboundCount, 0);
        const afterDuplicateCommits = await branchCommits(
          "draft", "draft", ["commit"],
        );
        assert.equal(
          afterDuplicateCommits.filter(({ type }) => type === "commit").length,
          1,
        );
        assert.equal(
          afterDuplicateCommits.every(({ tree: ownerTree }) =>
            ownerTree === "draft"
          ),
          true,
        );
        await native.client.mergeBranch("main", "draft", true, "draft");
        await native.awaitSynced();
        assert.equal(
          (await native.client.checkpoint("draft")).commits
            .some(({ type, tree: ownerTree }) =>
              type === "settlement" && ownerTree === "draft"
            ),
          true,
        );
        await until(
          () => view.root === "preserved-after-duplicate",
          "preserved duplicate fork state",
        );

        await native.client.openView("required-string", "draft");
        const refusedClear = await native.client.request({
          command: "clear", tree: "draft", path: [],
        });
        assert.equal(refusedClear.ok, false);
        assert.equal(view.root, "preserved-after-duplicate");
        assert.deepEqual(await command({ command: "read", path: ["label"] }), {
          present: true,
          value: { kind: "string", value: "branch-main" },
        });
        const main = await command({ command: "read", path: ["label"] });
        assert.deepEqual(main, {
          present: true,
          value: { kind: "string", value: "branch-main" },
        });
        for (const request of [
          { command: "create-data-store", name: "secondary" },
          { command: "create-map", store: "secondary", name: "map" },
          {
            command: "create-tree", name: "draft", store: "secondary",
            schema: stringSchema, view: stringSchema,
            initialRoot: { kind: "string", value: "duplicate" },
          },
        ]) {
          const reply = await native.client.request(request);
          assert.equal(reply.ok, false);
          assert.equal(reply.error.code, "facade-error");
        }
        const published = await command({ command: "summarize" });
        assert.equal(typeof published.version, "string");
      } finally {
        await native?.close();
        cleanupOwned(containers);
      }
    }
  });
});

test("service profile publishes the local M6 branch boundary", () => {
  assert.deepEqual(branchSupportedFeatures, [
    "runtime-local-checkouts",
    "local-fork-rebase-merge",
    "checkout-scoped-transactions-and-revertibles",
    "branch-and-revertible-history-retention",
    "local-branch-reconnect",
    "merged-branch-summary-continuation",
  ]);
  assert.deepEqual(branchExcludedFeatures, [
    "shared-branches",
    "persisted-branches",
    "branch-wire-apis",
    "branch-schema-authoring",
    "cross-runtime-or-tree-merge",
    "portable-branch-handles-and-revertibles",
    "historical-checkouts",
  ]);
  for (const feature of branchSupportedFeatures) {
    assert(supportedFeatures.includes(feature), `Missing support: ${feature}`);
    assert(!excludedFeatures.includes(feature), `Support excluded: ${feature}`);
  }
  for (const feature of branchExcludedFeatures) {
    assert(excludedFeatures.includes(feature), `Missing exclusion: ${feature}`);
  }
  assert(!excludedFeatures.includes("public-local-branch-apis"));
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

test("openSession scopes real default compression without changing legacy callers", {
  timeout: 60_000,
}, async () => {
  await withLocalFloodgate(async (config) => {
    const containers = [];
    try {
      const legacy = await openSession(config, containers);
      assert.deepEqual(legacy.effectiveRuntimeOptions.compression, {
        mode: "legacy-disabled",
        minimumBatchSizeInBytes: Infinity,
        chunkSizeInBytes: 204800,
        compressionAlgorithm: "lz4",
      });
      const defaults = await openSession(
        config,
        containers,
        legacy.container.resolvedUrl.id,
        false,
        { runtimeOptionMode: "default-compression" },
      );
      assert.deepEqual(defaults.effectiveRuntimeOptions.compression, {
        mode: "default-compression",
        minimumBatchSizeInBytes: 614400,
        chunkSizeInBytes: 204800,
        compressionAlgorithm: "lz4",
      });
      assert.deepEqual(
        defaults.effectiveRuntimeOptions.summaryOptions,
        legacy.effectiveRuntimeOptions.summaryOptions,
      );
      assert.equal(defaults.effectiveRuntimeOptions.enableRuntimeIdCompressor, "on");
    } finally {
      cleanupOwned(containers);
    }
  });
});

test("upstream adapter owns local forks and publishes only merged edits", {
  timeout: 60_000,
}, async () => {
  await withLocalFloodgate(async (config) => {
    const containers = [];
    try {
      const authorSession = await openSession(config, containers);
      const peerSession = await openSession(
        config,
        containers,
        authorSession.container.resolvedUrl.id,
      );
      const author = upstreamAdapter(authorSession);
      const peer = upstreamAdapter(peerSession);
      const titleOf = (tree) =>
        tree.value.fields.find(([name]) => name === "title")[1].value;
      await author.awaitSynced();
      await peer.awaitSynced();
      const beforeTitle = peerSession.data.view.root.title;

      assert.equal((await author.fork("main", "parent")).status, "BranchValid");
      assert.equal((await author.fork("parent", "draft")).status, "BranchValid");
      const edit = await author.branchEdit("draft", {
        kind: "object-set",
        path: ["title"],
        value: "draft",
      });
      assert.equal(edit.outboundCount, 0);
      assert.equal(titleOf(edit.tree), "draft");
      const retained = await author.retainLastLocalCommit("draft-edit", "draft");
      assert.equal(retained.factoryAvailable, true);
      await author.disposeBranch("parent");
      await peer.checkpoint();
      assert.equal(peerSession.data.view.root.title, beforeTitle);

      await author.rebaseBranch("draft", "main");
      const merge = await author.mergeBranch("main", "draft", true);
      assert.equal(titleOf(merge.targetTree), "draft");
      assert.equal(authorSession.data.view.root.title, "draft");
      await author.awaitSynced();
      const accepted = await author.checkpoint();
      await peer.awaitSynced(accepted.sequenceNumber);
      assert.equal(merge.disposed, true);
      await peer.checkpoint();
      assert.equal(peerSession.data.view.root.title, "draft");
    } finally {
      cleanupOwned(containers);
    }
  });
});

test("upstream local forks preserve seeded same-array move state", {
  timeout: 60_000,
}, async () => {
  await withLocalFloodgate(async (config) => {
    const containers = [];
    try {
      const session = await openSession(
        config,
        containers,
        undefined,
        false,
        { store: arrayServiceStore },
      );
      const adapter = upstreamAdapter(session);
      await adapter.arrayInsert(["left"], 0, [
        { kind: "string", value: "zero" },
        { kind: "string", value: "one" },
        { kind: "string", value: "two" },
      ]);
      await adapter.fork("main", "draft");
      const edit = await adapter.branchEdit("draft", {
        kind: "array-move",
        sourcePath: ["left"],
        sourceStart: 0,
        sourceEnd: 1,
        destinationPath: ["left"],
        destinationGap: 2,
      });
      assert.equal(edit.outboundCount, 0);
    } finally {
      cleanupOwned(containers);
    }
  });
});

test("local branch service cell moves within a seeded array", {
  timeout: 120_000,
}, async () => {
  const fixture = JSON.parse(await readFile(new URL(
    "../../test/fixtures/shared_tree/cases/array-schema-content.json",
    import.meta.url,
  ), "utf8"));
  const arrayViewSchema = fixture.input.schemas.objectArrays;
  await withLocalFloodgate(async (config) => {
    const row = await runLocalBranchConcurrentCell(config, {
      runId: "same-array-move-service-cell",
      arrayViewSchema,
    }, {
      id: "local-branch:upstream<->javascript:same-array-move:unrelated:branch-first:rebase",
      authors: ["upstream", "javascript"],
      fieldKind: "same-array-move",
      conflictClass: "unrelated",
      order: "branch-first",
      strategy: "rebase",
    });
    assert.equal(validateLocalBranchRow(row, row.id), row);
  });
});

test("local branch service cell applies a transaction", {
  timeout: 120_000,
}, async () => {
  const fixture = JSON.parse(await readFile(new URL(
    "../../test/fixtures/shared_tree/cases/array-schema-content.json",
    import.meta.url,
  ), "utf8"));
  await withLocalFloodgate(async (config) => {
    const row = await runLocalBranchConcurrentCell(config, {
      runId: "transaction-service-cell",
      arrayViewSchema: fixture.input.schemas.objectArrays,
    }, {
      id: "local-branch:upstream<->javascript:transaction:overlapping:branch-first:rebase",
      authors: ["upstream", "javascript"],
      fieldKind: "transaction",
      conflictClass: "overlapping",
      order: "branch-first",
      strategy: "rebase",
    });
    assert.equal(validateLocalBranchRow(row, row.id), row);
  });
});

test("local branch service cell resolves overlapping object edits", {
  timeout: 120_000,
}, async () => {
  const fixture = JSON.parse(await readFile(new URL(
    "../../test/fixtures/shared_tree/cases/schema-profile.json",
    import.meta.url,
  ), "utf8"));
  await withLocalFloodgate(async (config) => {
    const row = await runLocalBranchConcurrentCell(config, {
      runId: "object-overlap-service-cell",
      viewSchema: fixture.input.summary.tree.indexes.tree.Schema
        .tree.SchemaString.content,
    }, {
      id: "local-branch:upstream<->javascript:object:overlapping:branch-first:rebase",
      authors: ["upstream", "javascript"],
      fieldKind: "object",
      conflictClass: "overlapping",
      order: "branch-first",
      strategy: "rebase",
    });
    assert.equal(validateLocalBranchRow(row, row.id), row);
  });
});

test("local branch service cell preserves identifier branch insertion", {
  timeout: 120_000,
}, async () => {
  const fixture = JSON.parse(await readFile(new URL(
    "../../test/fixtures/shared_tree/cases/identifier-schema.json",
    import.meta.url,
  ), "utf8"));
  await withLocalFloodgate(async (config) => {
    const row = await runLocalBranchConcurrentCell(config, {
      runId: "identifier-branch-service-cell",
      identifierViewSchema: JSON.stringify(fixture.input.schema),
    }, {
      id: "local-branch:upstream<->javascript:identifier:unrelated:branch-first:rebase",
      authors: ["upstream", "javascript"],
      fieldKind: "identifier",
      conflictClass: "unrelated",
      order: "branch-first",
      strategy: "rebase",
    });
    assert.equal(validateLocalBranchRow(row, row.id), row);
  });
});

test("native local branch handles undo before merge", {
  timeout: 180_000,
}, async () => {
  const fixture = JSON.parse(await readFile(new URL(
    "../../test/fixtures/shared_tree/cases/schema-profile.json",
    import.meta.url,
  ), "utf8"));
  const viewSchema = fixture.input.summary.tree.indexes.tree.Schema
    .tree.SchemaString.content;
  await withLocalFloodgate(async (config) => {
    for (const implementation of ["javascript", "erlang"]) {
      await runLocalBranchLifetimeCell(config, {
        runId: `branch-undo-${implementation}`,
        viewSchema,
      }, implementation, "branch-undo-before-merge");
    }
  });
});

test("native branch merge is accepted once before reconnect", {
  timeout: 180_000,
}, async () => {
  const fixture = JSON.parse(await readFile(new URL(
    "../../test/fixtures/shared_tree/cases/schema-profile.json",
    import.meta.url,
  ), "utf8"));
  const viewSchema = fixture.input.summary.tree.indexes.tree.Schema
    .tree.SchemaString.content;
  await withLocalFloodgate(async (config) => {
    for (const writer of ["javascript", "erlang"]) {
      const result = await runLocalBranchReconnectCell(config, {
        runId: `branch-reconnect-${writer}`,
        viewSchema,
      }, writer, "accepted-before-drop");
      assert.equal(result.mergeSubmissionCount, 1);
    }
  });
});

test("all real local branch sections pass the final validator", {
  timeout: 1_800_000,
}, async () => {
  const [objectFixture, mapFixture, arrayFixture, identifierFixture] =
    await Promise.all([
      "schema-profile.json",
      "map-schema-content.json",
      "array-schema-content.json",
      "identifier-schema.json",
    ].map(async (name) => JSON.parse(await readFile(new URL(
      `../../test/fixtures/shared_tree/cases/${name}`,
      import.meta.url,
    ), "utf8"))));
  const context = {
    runId: "local-branch-final-sections",
    viewSchema: objectFixture.input.summary.tree.indexes.tree.Schema
      .tree.SchemaString.content,
    mapViewSchema: mapFixture.input.schemas.objectContainedMap,
    arrayViewSchema: arrayFixture.input.schemas.objectArrays,
    identifierViewSchema: JSON.stringify(identifierFixture.input.schema),
  };
  await withLocalFloodgate(async (config) => {
    const local = await runLocalBranchScenarios(config, context);
    const localBranchReloadMatrix =
      await runLocalBranchReloadMatrix(config, context);
    const report = {
      localBranchIsolation: local.isolation,
      localBranchConcurrent: local.concurrent,
      localBranchLifetime: local.lifetime,
      localBranchReconnect: local.reconnect,
      localBranchReloadMatrix,
    };
    if (process.env.TASK9_SECTION_ARTIFACT) {
      await writeFile(
        process.env.TASK9_SECTION_ARTIFACT,
        `${JSON.stringify(report)}\n`,
        { mode: 0o600 },
      );
    }
    assert.equal(validateLocalBranchSections(report), report);
  });
});

test("native clients own local forks and publish ordinary merged edits", {
  timeout: 120_000,
}, async () => {
  const schemaFixture = JSON.parse(await readFile(new URL(
    "../../test/fixtures/shared_tree/cases/schema-profile.json",
    import.meta.url,
  ), "utf8"));
  const viewSchema = schemaFixture.input.summary.tree.indexes.tree.Schema
    .tree.SchemaString.content;
  for (const target of ["javascript", "erlang"]) {
    await withLocalFloodgate(async (config) => {
      const containers = [];
      let native;
      try {
        const creator = await openSession(config, containers);
        const documentId = creator.container.resolvedUrl.id;
        await publishUpstreamSummary(
          config,
          containers,
          documentId,
          `Task 9 ${target} branch bootstrap`,
        );
        const peerSession = await openSession(config, containers, documentId);
        const jwt = (await tokenProvider(config).fetchOrdererToken(
          config.tenantId,
          documentId,
        )).jwt;
        native = await nativeAdapter(target, config, {
          runId: `native-branch-${target}`,
          documentId,
          tenant: config.tenantId,
          viewSchema,
        }, jwt);
        const peer = upstreamAdapter(peerSession);
        await native.awaitSynced();
        await peer.awaitSynced();

        await native.fork("main", "draft");
        const edit = await native.branchEdit("draft", {
          kind: "object-set",
          path: ["title"],
          value: "draft",
        });
        assert.equal(edit.outboundCount, 0);
        await peer.set(["rating"], 17);
        await peer.awaitSynced();
        await native.awaitSynced();
        assert.equal(peerSession.data.view.root.title, "");

        await native.rebaseBranch("draft", "main");
        await native.mergeBranch("main", "draft", true);
        await native.awaitSynced();
        await peer.awaitSynced();
        assert.equal(peerSession.data.view.root.title, "draft");
        assert.equal(peerSession.data.view.root.rating, 17);
      } finally {
        await native?.close();
        cleanupOwned(containers);
      }
    });
  }
});

test("native retained commits stay with the requested checkout", {
  timeout: 180_000,
}, async () => {
  const schemaFixture = JSON.parse(await readFile(new URL(
    "../../test/fixtures/shared_tree/cases/schema-profile.json",
    import.meta.url,
  ), "utf8"));
  const viewSchema = schemaFixture.input.summary.tree.indexes.tree.Schema
    .tree.SchemaString.content;
  for (const target of ["javascript", "erlang"]) {
    await withLocalFloodgate(async (config) => {
      const containers = [];
      let native;
      try {
        const creator = await openSession(config, containers);
        const documentId = creator.container.resolvedUrl.id;
        await publishUpstreamSummary(
          config,
          containers,
          documentId,
          `Task 9 ${target} checkout retention bootstrap`,
        );
        const peerSession = await openSession(config, containers, documentId);
        const jwt = (await tokenProvider(config).fetchOrdererToken(
          config.tenantId,
          documentId,
        )).jwt;
        native = await nativeAdapter(target, config, {
          runId: `native-checkout-retention-${target}`,
          documentId,
          tenant: config.tenantId,
          viewSchema,
        }, jwt);
        const peer = upstreamAdapter(peerSession);
        await native.awaitSynced();
        await peer.awaitSynced();

        await native.set(["rating"], 7);
        await native.fork("main", "first");
        await native.fork("main", "second");
        await native.branchEdit("first", {
          kind: "object-set",
          value: "first",
        });
        await native.branchEdit("second", {
          kind: "object-set",
          value: "second",
        });
        await native.retainLastLocalCommit("main-edit", "main");
        await native.retainLastLocalCommit("first-edit", "first");
        const firstUndo = await native.revert("first-edit", true);
        assert.equal(firstUndo.outboundCount, 0);
        await native.mergeBranch("main", "first", true);
        await native.awaitSynced();
        await peer.awaitSynced();
        assert.equal(peerSession.data.view.root.title, "");
        assert.equal(peerSession.data.view.root.rating, 7);

        await native.mergeBranch("main", "second", true);
        await native.awaitSynced();
        await peer.awaitSynced();
        assert.equal(peerSession.data.view.root.title, "second");

        const mainUndo = await native.revert("main-edit", true);
        assert.equal(mainUndo.outboundCount, 1);
        await native.awaitSynced();
        await peer.awaitSynced();
        assert.equal(peerSession.data.view.root.rating, 0);
      } finally {
        await native?.close();
        cleanupOwned(containers);
      }
    });
  }
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
