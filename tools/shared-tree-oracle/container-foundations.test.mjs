import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import * as foundations from "./container-foundations.mjs";

const { captureContainerFoundations } = foundations;

const casesDirectory = new URL("../../test/fixtures/shared_tree/cases/", import.meta.url);

async function fixture(name) {
  return JSON.parse(await readFile(new URL(`${name}.json`, casesDirectory), "utf8"));
}

test("container foundations reuse captured inputs and upstream structural consumers", async () => {
  const bootstrap = await fixture("bootstrap-map-handles");
  const batched = await fixture("batched-commits");
  const capture = await captureContainerFoundations([bootstrap, batched]);

  assert.equal(capture.formatVersion, 1);
  assert.deepEqual(capture.reference, {
    package: "@fluidframework/tree",
    version: "3.1.0",
    commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
  });
  assert.equal(capture.id, "container-foundations");
  assert.equal(capture.domain, "container");
  assert.equal(capture.input.service, "FluidContainerRuntime");
  assert.strictEqual(
    capture.input.initialSnapshot,
    bootstrap.input.decoderInput.initialSnapshot,
  );
  assert.strictEqual(
    capture.input.bootstrapMessages,
    bootstrap.input.decoderInput.bootstrapMessages,
  );
  assert.strictEqual(
    capture.input.groupedWireMessages,
    batched.input.decoderInput.groupedWireMessages,
  );
  assert(capture.input.decodeCases.length > 0);
  assert(capture.input.encodeCases.length > 0);
  assert(capture.input.handleCases.length > 0);
  assert(capture.expected.observations.length > 0);
  assert(capture.expected.observations.some(
    ({ kind }) => kind === "bootstrapMessages",
  ));
  assert.equal(capture.raw.consumers.alias.accepted, true);
  assert.equal(capture.raw.consumers.datastoreAttach.accepted, true);
  assert.equal(capture.raw.consumers.channelAttach.accepted, true);
  assert.equal(capture.raw.consumers.groupedBatch.accepted, true);
  assert.equal(capture.raw.consumers.handle.absolute, "/A/_C");
  assert.equal(capture.raw.consumers.handle.relative, "/A/_C");
  assert.deepEqual(capture.raw.consumers.handle.escapedParts, ["A/B", "café"]);
  assert.deepEqual(capture.expected.observations.at(-1), {
    kind: "bootstrap",
    mapType: "https://graph.microsoft.com/types/map",
    mapSnapshotFormatVersion: "0.2",
    mapPackageVersion: "3.1.0",
    valueType: "Plain",
    handleType: "__fluid_handle__",
    handlePath: "/A/_C",
    route: { dataStoreId: "A", channelId: "_C" },
    treeType: "https://graph.microsoft.com/types/tree",
    treeSnapshotFormatVersion: "0.0.0",
    treePackageVersion: "3.1.0",
  });
});

test("container foundations validator requires complete paired evidence", async () => {
  assert.equal(typeof foundations.validateContainerFoundationsCase, "function");
  const bootstrap = await fixture("bootstrap-map-handles");
  const batched = await fixture("batched-commits");
  const capture = await captureContainerFoundations([bootstrap, batched]);
  assert.doesNotThrow(() => foundations.validateContainerFoundationsCase(capture));
  assert.doesNotThrow(() =>
    foundations.validateContainerFoundationsCase(
      JSON.parse(JSON.stringify(capture)),
    ));

  for (const mutate of [
    (value) => { value.input.service = "LocalDeltaConnectionServer"; },
    (value) => { value.expected.observations.reverse(); },
    (value) => { delete value.expected.observations[0].messages; },
    (value) => { value.raw.consumers.alias.message.contents.internalId = "wrong"; },
    (value) => { value.input.handleCases.pop(); },
    (value) => {
      value.input.groupedWireMessages.push(
        structuredClone(value.input.groupedWireMessages[0]),
      );
    },
    (value) => { value.extra = true; },
  ]) {
    const changed = structuredClone(capture);
    mutate(changed);
    assert.throws(
      () => foundations.validateContainerFoundationsCase(changed),
      /container-foundations/,
    );
  }
});

test("container foundations require the real bootstrap and batch captures", async () => {
  const bootstrap = await fixture("bootstrap-map-handles");
  const batched = await fixture("batched-commits");

  await assert.rejects(captureContainerFoundations([]), /bootstrap-map-handles/);
  await assert.rejects(captureContainerFoundations([bootstrap]), /batched-commits/);
  const changed = structuredClone(batched);
  changed.reference.commit = "wrong";
  await assert.rejects(
    captureContainerFoundations([bootstrap, changed]),
    /reference/,
  );
});
