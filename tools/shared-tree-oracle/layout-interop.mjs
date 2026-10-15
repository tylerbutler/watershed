import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { runCreatorProbe } from "./creation.mjs";
import {
  arrayServiceStore, openSession, tokenProvider, withLocalFloodgate,
} from "./service.mjs";
import { arrayTreeConfig } from "./schema.mjs";
import { nativeAdapter, until } from "./interop-scenarios.mjs";
import { loadInteropProfile } from "./interop.mjs";

const runId = randomUUID();
const output = join(import.meta.dirname, ".output/layouts", runId);
const { profile, profileDigest } = await loadInteropProfile(join(
  import.meta.dirname, "../../test/fixtures/shared_tree/profile.json",
));
const fixture = JSON.parse(await readFile(new URL(
  "../../test/fixtures/shared_tree/cases/array-schema-content.json",
  import.meta.url,
), "utf8"));
const viewSchema = fixture.input.schemas.objectArrays;
const schema = JSON.parse(viewSchema);
const array = (schemaId) => ({ kind: "array", schemaId, elements: [] });
const root = {
  kind: "object",
  schemaId: "org.watershed.shared-tree.m3.Root",
  fields: [
    ["byKey", {
      kind: "map", schemaId: "org.watershed.shared-tree.m3.ArrayMap", entries: [],
    }],
    ["left", array("org.watershed.shared-tree.m3.Items")],
    ["narrow", array("org.watershed.shared-tree.m3.Points")],
    ["right", array("org.watershed.shared-tree.m3.Items")],
  ],
};
const point = (label, x) => ({
  kind: "object", schemaId: "org.watershed.shared-tree.m3.Point",
  fields: [
    ["label", { kind: "string", value: label }],
    ["x", { kind: "number", value: x }],
  ],
});
const handle = (url) => ({ type: "__fluid_handle__", url });

async function openNativeGraph(native) {
  await native.client.openMap("catalog", handle("/B/root"));
  assert.deepEqual(await native.client.sharedMapGet("catalog", "tree"), {
    present: true, value: handle("/B/items"),
  });
  await native.client.openMap("child", handle("/B/child"));
  assert.deepEqual(await native.client.sharedMapGet("child", "value"), {
    present: true, value: "initial child",
  });
  assert.deepEqual(await native.client.sharedMapGet("child", "parent"), {
    present: true, value: handle("/C/root"),
  });
  await native.client.openMap("parent", handle("/C/root"));
  assert.deepEqual(await native.client.sharedMapGet("parent", "parent"), {
    present: true, value: handle("/B/root"),
  });
  await native.client.openTree("layout", handle("/B/items"), schema);
}

async function upstreamGraph(session) {
  const catalog = await session.data.bootstrap.get("catalog").get();
  const entryPoint = await session.runtime.getAliasedDataStoreEntryPoint("catalog");
  const aliased = await entryPoint.get();
  assert.equal(aliased.root.handle.absolutePath, catalog.handle.absolutePath);
  const child = await catalog.get("child").get();
  assert.equal(child.get("value"), "initial child");
  const parent = await child.get("parent").get();
  const cycle = await parent.get("parent").get();
  assert.equal(cycle.handle.absolutePath, catalog.handle.absolutePath);
  const tree = await catalog.get("tree").get();
  return tree.viewWith(arrayTreeConfig);
}

async function continueReader(reader, view, writer) {
  const left = view.root.left.length;
  const right = view.root.right.length;
  if (reader.client) {
    await reader.client.arrayInsert(["right"], right, [point("continued", 3)], "layout");
    await reader.awaitSynced();
  } else {
    reader.root.right.insertAt(right, { label: "continued", x: 3 });
  }
  await until(() => view.root.right.length === right + 1, "fresh-reader insertion");
  const moved = view.root.right[right];
  if (reader.client) {
    await reader.client.arrayMove(["right"], right, right + 1, ["left"], left, "layout");
    await reader.awaitSynced();
  } else {
    reader.root.left.moveRangeToIndex(left, right, right + 1, reader.root.right);
  }
  await until(() => view.root.left.length === left + 1, "fresh-reader move");
  assert.equal(view.root.left[left], moved, "fresh-reader move replaced node identity");
  if (reader.client) {
    await reader.client.arrayRemove(["left"], left, left + 1, "layout");
    await reader.awaitSynced();
  } else {
    reader.root.left.removeRange(left, left + 1);
  }
  await until(async () =>
    view.root.left.length === left && view.root.right.length === right
      && (await writer.client.arrayValues(["left"], "layout")).length === left
      && (await writer.client.arrayValues(["right"], "layout")).length === right,
  "fresh-reader continuation settled");
}

async function scenario(config, creator) {
  const containers = [];
  const natives = [];
  const results = [];
  let scenarioError;
  try {
    const { jwt: token } = await tokenProvider(config).fetchStorageToken(config.tenantId);
    const created = await runCreatorProbe(creator, {
      baseUrl: config.httpUrl, tenant: config.tenantId, token, schema: viewSchema,
      root, expected: "success", layout: "graph",
    });
    assert.equal(created.ok, true);
    const documentId = created.documentId;
    const { jwt } = await tokenProvider(config).fetchOrdererToken(config.tenantId, documentId);
    const descriptor = { runId, documentId, tenant: config.tenantId, viewSchema };
    const source = await openSession(config, containers, documentId, false, {
      cache: false, store: arrayServiceStore,
    });
    const view = await upstreamGraph(source);
    const writer = await nativeAdapter(creator, config, descriptor, jwt);
    natives.push(writer);
    await writer.awaitSynced();
    await openNativeGraph(writer);
    await writeFile(join(output, `${creator}.initial-summary.json`),
      JSON.stringify(await writer.client.request({ command: "pending-summary-evidence" })),
      { mode: 0o600 });

    for (const checkpoint of ["initial", "native-summary"]) {
      for (const reader of ["upstream", "javascript", "erlang"]) {
        const expectedLeft = checkpoint === "initial" ? [] : [point("two", 2)];
        const expectedRight = checkpoint === "initial" ? [] : [point("one", 1)];
        if (reader === "upstream") {
          const reopened = await openSession(config, containers, documentId, false, {
            cache: false, store: arrayServiceStore,
          });
          const fresh = await upstreamGraph(reopened);
          assert.deepEqual([...fresh.root.left].map((item) => item.label),
            checkpoint === "initial" ? [] : ["two"]);
          assert.deepEqual([...fresh.root.right].map((item) => item.label),
            checkpoint === "initial" ? [] : ["one"]);
          assert.equal(reopened.data.view.root.left.length, 0);
          await continueReader(fresh, view, writer);
          await until(() => !reopened.container.isDirty, "upstream continuation acknowledged");
          fresh.dispose();
        } else {
          const fresh = await nativeAdapter(reader, config, descriptor, jwt);
          try {
            await fresh.awaitSynced();
            await openNativeGraph(fresh);
            assert.deepEqual(await fresh.client.arrayValues(["left"], "layout"), expectedLeft);
            assert.deepEqual(await fresh.client.arrayValues(["right"], "layout"), expectedRight);
            assert.deepEqual(await fresh.client.arrayValues(["left"]), []);
            await continueReader(fresh, view, writer);
          } finally {
            await fresh.close();
          }
        }
        assert.equal(source.data.view.root.left.length, 0);
        assert.equal(source.data.view.root.right.length, 0);
        const result = { creator, reader, checkpoint, documentId, continued: true };
        results.push(result);
        await writeFile(join(output, `${creator}-${checkpoint}-${reader}.json`),
          JSON.stringify(result), { mode: 0o600 });
      }
      if (checkpoint === "initial") {
        await writer.client.arrayInsert(["left"], 0, [point("one", 1), point("two", 2)], "layout");
        await writer.awaitSynced();
        await until(() => view.root.left.length === 2, `${creator} secondary insertion`);
        const moved = view.root.left[0];
        await writer.client.arrayMove(["left"], 0, 1, ["right"], 0, "layout");
        await writer.awaitSynced();
        await until(() => view.root.right.length === 1, `${creator} secondary move`);
        assert.equal(view.root.right[0], moved, "cross-array move replaced node identity");
        assert.equal(view.root.left[0].label, "two");
        const evidence = await writer.client.request({ command: "pending-summary-evidence" });
        await writeFile(join(output, `${creator}.summary.json`),
          JSON.stringify(evidence), { mode: 0o600 });
        const version = await writer.summarize();
        assert(version.length > 0);
      }
    }
    const settled = await writer.checkpoint();
    assert.equal(settled.inflightSubmissionCount, 0);
    await writeFile(join(output, `${creator}.transport.json`), JSON.stringify({
      settled, transport: writer.client.gate.evidence(),
    }), { mode: 0o600 });
    view.dispose();
    return results;
  } catch (error) {
    scenarioError = error;
    await writeFile(join(output, `${creator}.failure.json`), JSON.stringify({
      creator, message: error.message, stack: error.stack,
      transport: natives.map((native) => native.client.gate.evidence()),
    }), { mode: 0o600 }).catch((captureError) => {
      throw new AggregateError([error, captureError], "layout failure capture failed");
    });
    throw error;
  } finally {
    const closed = await Promise.allSettled(natives.map((native) => native.close()));
    for (const container of containers.toReversed()) container.close();
    const failures = closed.filter((result) => result.status === "rejected")
      .map((result) => result.reason);
    if (failures.length > 0) {
      throw new AggregateError(
        [...(scenarioError === undefined ? [] : [scenarioError]), ...failures],
        "layout client cleanup failed",
      );
    }
  }
}

await mkdir(output, { recursive: true });
const results = await withLocalFloodgate(async (config) => {
  const results = [];
  for (const creator of ["javascript", "erlang"]) {
    results.push(...await scenario(config, creator));
  }
  return results;
});
assert.equal(results.length, 12);
await writeFile(join(output, "report.json"), JSON.stringify({
  runId, profileDigest, reference: profile.reference, service: profile.service, results,
}), {
  mode: 0o600,
});
console.log(`Declared container layout interoperability passed: ${results.length} cells (${runId})`);
