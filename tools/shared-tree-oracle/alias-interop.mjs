import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import {
  arrayServiceStore,
  handleGraphStore,
  openSession,
  tokenProvider,
  withLocalFloodgate,
} from "./service.mjs";
import {
  nativeAdapter,
  publishUpstreamSummary,
  until,
} from "./interop-scenarios.mjs";

const runId = randomUUID();
const output = join(import.meta.dirname, ".output/aliases", runId);
const fixture = JSON.parse(await readFile(new URL(
  "../../test/fixtures/shared_tree/cases/array-schema-content.json",
  import.meta.url,
), "utf8"));
const schema = JSON.parse(fixture.input.schemas.objectArrays);
const viewSchema = JSON.stringify(schema);
const emptyItems = {
  kind: "array", schemaId: "org.watershed.shared-tree.m3.Items", elements: [],
};
const initialRoot = {
  kind: "object",
  schemaId: "org.watershed.shared-tree.m3.Root",
  fields: [
    ["byKey", {
      kind: "map", schemaId: "org.watershed.shared-tree.m3.ArrayMap", entries: [],
    }],
    ["left", emptyItems],
    ["narrow", {
      kind: "array", schemaId: "org.watershed.shared-tree.m3.Points", elements: [],
    }],
    ["right", emptyItems],
  ],
};

async function aliasedRoot(session, alias) {
  const handle = await session.runtime.getAliasedDataStoreEntryPoint(alias);
  return handle === undefined ? undefined : handle.get();
}

async function cell(config, target, mode) {
  const id = `${target}-${mode}`;
  const containers = [];
  let native;
  let reloaded;
  let reloadEvidence;
  try {
    const session = await openSession(config, containers, undefined, false, {
      store: arrayServiceStore,
    });
    const documentId = session.container.resolvedUrl.id;
    await publishUpstreamSummary(config, containers, documentId, id, {
      store: arrayServiceStore,
    });
    const { jwt } = await tokenProvider(config)
      .fetchOrdererToken(config.tenantId, documentId);
    const descriptor = { runId, documentId, tenant: config.tenantId, viewSchema };
    native = await nativeAdapter(target, config, descriptor, jwt);
    await native.awaitSynced();
    const rootHandle = await native.client.createDataStore("store");
    await native.client.dataStoreRoot("store", "entry");
    const mapHandle = await native.client.createMap("child", "store");
    const treeHandle = await native.client.createTree({
      name: "tree", store: "store", schema, view: schema, initialRoot,
    });
    await native.client.sharedMapSet("entry", "value", id);
    await native.client.sharedMapSet("entry", "child", mapHandle);
    await native.client.sharedMapSet("entry", "tree", treeHandle);
    await native.client.sharedMapSet("child", "parent", rootHandle);
    const alias = `alias-${id}`;
    let initialOutcome;
    if (mode.startsWith("attached-")) {
      await native.client.openMap("bootstrap", {
        type: "__fluid_handle__", url: session.data.bootstrap.handle.absolutePath,
      });
      await native.client.sharedMapSet("bootstrap", "published-graph", rootHandle);
      await native.awaitSynced();
    }
    if (mode.startsWith("retry-")) {
      const competitor = await session.runtime.createDataStore(handleGraphStore.type);
      assert.equal(await competitor.trySetAlias(`${alias}-taken`), "Success");
      initialOutcome = await native.client.trySetAlias("store", `${alias}-taken`);
      assert.equal(initialOutcome, "Conflict");
      await native.awaitSynced();
    }
    const reconnect = mode.includes("reconnect-");
    const accepted = mode.endsWith("-accepted");
    let sourceOutcome;
    let competitor;
    if (mode === "race") {
      competitor = await session.runtime.createDataStore(handleGraphStore.type);
      const competitorRoot = await competitor.entryPoint.get();
      competitorRoot.root.set("value", "source-winner");
      native.client.gate.hold("outbound", "op");
    }
    if (reconnect) {
      native.client.gate.hold(
        accepted ? "inbound" : "outbound", "op",
      );
    }
    const pending = native.client.trySetAlias("store", alias);
    if (mode === "race") {
      await until(() => native.client.gate.evidence().held.some(
        ({ direction, kind }) => direction === "outbound" && kind === "op",
      ), `${id} held native claim`);
      sourceOutcome = await competitor.trySetAlias(alias);
      assert.equal(sourceOutcome, "Success");
      await native.client.gate.release("outbound");
    }
    let beforeReconnect;
    let afterReconnect;
    if (reconnect) {
      await until(() => native.client.gate.evidence().held.some(
        ({ kind }) => kind === "op",
      ), `${id} held alias operation`);
      if (accepted) {
        await until(async () => (await aliasedRoot(session, alias)) !== undefined,
          `${id} source saw server acceptance`);
      }
      beforeReconnect = (await native.checkpoint()).clientId;
      await native.disconnect();
      await native.reconnect();
      afterReconnect = (await native.checkpoint()).clientId;
      assert.notEqual(afterReconnect, beforeReconnect);
    }
    const outcome = await pending;
    assert.equal(outcome, mode === "race" ? "Conflict" : "Success");
    await native.awaitSynced();
    const resolved = await aliasedRoot(session, alias);
    assert(resolved, `${id} missing source alias resolution`);
    assert.equal(resolved.root.get("value"),
      mode === "race" ? "source-winner" : id);
    if (mode === "race") {
      assert.equal(await competitor.trySetAlias(alias), "Success");
      assert.equal(await competitor.trySetAlias(`${alias}-different`), "AlreadyAliased");
      assert.equal(await native.client.trySetAlias("store", "A"), "Conflict",
        `${id} alias hid an existing datastore identity`);
      assert.equal(await native.client.trySetAlias("store", `${alias}-retry`), "Success");
    } else {
      assert.equal(resolved.root.handle.absolutePath, rootHandle.url);
      const child = await resolved.root.get("child").get();
      const parent = await child.get("parent").get();
      assert.equal(parent.handle.absolutePath, rootHandle.url);
      assert.equal(parent.get("value"), id);
      const tree = await resolved.root.get("tree").get();
      assert.equal(tree.attributes.type, "https://graph.microsoft.com/types/tree");
      assert.equal(await native.client.trySetAlias("store", alias), "Success");
      assert.equal(await native.client.trySetAlias("store", `${alias}-different`),
        "AlreadyAliased");
      const competitor = await session.runtime.createDataStore(handleGraphStore.type);
      assert.equal(await competitor.trySetAlias(alias), "Conflict",
        `${id} source overwrote a native alias`);
    }
    await native.awaitSynced();
    const summaryEvidence = await native.client.request({
      command: "pending-summary-evidence",
    });
    await writeFile(join(output, `${id}.summary.json`),
      JSON.stringify(summaryEvidence), { mode: 0o600 });
    const version = await native.summarize();
    assert(version.length > 0, `${id} native summary was not published`);
    const reopened = await openSession(config, containers, documentId, false, {
      cache: false, store: arrayServiceStore,
    });
    reloadEvidence = {
      initialSequenceNumber: reopened.container.deltaManager.initialSequenceNumber,
      lastSequenceNumber: reopened.container.deltaManager.lastSequenceNumber,
      aliases: [...reopened.runtime.channelCollection.aliases],
    };
    const restored = await aliasedRoot(reopened, alias);
    assert.equal(restored.root.get("value"),
      mode === "race" ? "source-winner" : id);
    reloaded = await nativeAdapter(target, config, descriptor, jwt);
    await reloaded.awaitSynced();
    const aliasHandle = { type: "__fluid_handle__", url: `/${alias}/root` };
    await reloaded.client.openMap("aliased", aliasHandle);
    assert.deepEqual(await reloaded.client.sharedMapGet("aliased", "value"), {
      present: true, value: mode === "race" ? "source-winner" : id,
    });
    const settled = await native.checkpoint();
    assert.equal(settled.inflightSubmissionCount, 0);
    const transport = native.client.gate.evidence();
    const result = {
      id, target, mode, documentId, alias, rootHandle, initialOutcome,
      outcome, sourceOutcome,
      beforeReconnect, afterReconnect, version, transport, settled,
    };
    await writeFile(join(output, `${id}.json`), JSON.stringify(result), { mode: 0o600 });
    return result;
  } catch (error) {
    await writeFile(join(output, `${id}.failure.json`), JSON.stringify({
      id, message: error.message, stack: error.stack,
      reloadEvidence,
      transport: native?.client.gate.evidence(),
    }), { mode: 0o600 }).catch((captureError) => {
      throw new AggregateError([error, captureError], `${id} failure capture failed`);
    });
    throw error;
  } finally {
    try {
      await reloaded?.close();
    } finally {
      try {
        await native?.close();
      } finally {
        for (const container of containers.toReversed()) container.close();
      }
    }
  }
}

await mkdir(output, { recursive: true });
const results = await withLocalFloodgate(async (config) => {
  const results = [];
  for (const target of ["javascript", "erlang"]) {
    for (const mode of [
      "success", "race", "reconnect-unsent", "reconnect-accepted",
      "attached-reconnect-unsent", "attached-reconnect-accepted",
      "retry-reconnect-unsent", "retry-reconnect-accepted",
    ]) {
      results.push(await cell(config, target, mode));
    }
  }
  return results;
});
assert.equal(results.length, 16);
await writeFile(join(output, "report.json"), JSON.stringify({ runId, results }), {
  mode: 0o600,
});
console.log(`Datastore alias interoperability passed: ${results.length} cells (${runId})`);
