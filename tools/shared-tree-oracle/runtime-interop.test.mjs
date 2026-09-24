import assert from "node:assert/strict";
import { mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import {
  runRuntimeInterop, validateRuntimeArtifact, validateRuntimeResult,
} from "./runtime-interop.mjs";

const reference = {
  package: "@fluidframework/tree",
  version: "3.1.0",
  commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
};
const scenarios = [
  "bootstrap-map-handle", "required-field", "optional-set",
  "optional-clear", "batched-commits",
];
const root = {
  title: "native-batched", enabled: true, rating: 3, marker: null,
  point: { x: 42, y: 0 },
};
function artifact(target) {
  return {
    target, reference,
    artifact: {
      formatVersion: 1, clientId: "native", sessionId: "session",
      bootstrapPath: "/A/root", treePath: "/A/_C",
      initialDocument: {
        snapshot: { tree: { trees: {} }, blobs: { source: "bytes" } },
        sequenceNumber: 0, minimumSequenceNumber: 0,
        bootstrapPath: "/A/root", treePath: "/A/_C",
      },
      mapHeader: { blobs: [], content: { tree: { type: "Plain", value: {
        type: "__fluid_handle__", url: "/A/_C",
      } } } },
      outbound: scenarios.map((id, index) => ({
        id, clientSequenceNumber: index + 1, referenceSequenceNumber: 2,
        type: "op", contents: { type: "component" }, metadata: null,
      })),
      root, pendingCount: 0, sequenceNumber: 9,
      treePositions: [
        { sequenceNumber: 4, indexInBatch: 0 },
        { sequenceNumber: 5, indexInBatch: 0 },
        { sequenceNumber: 6, indexInBatch: 0 },
        ...[0, 1, 2].map((indexInBatch) => ({ sequenceNumber: 7, indexInBatch })),
        { sequenceNumber: 9, indexInBatch: 0 },
      ],
    },
  };
}

test("runtime artifacts require fresh output for each target and all scenarios", () => {
  validateRuntimeArtifact(artifact("javascript"), "javascript");
  for (const change of [
    (value) => { value.target = "erlang"; },
    (value) => { value.artifact.outbound.pop(); },
    (value) => { value.artifact.outbound[1].contents = null; },
    (value) => { delete value.artifact.initialDocument; },
  ]) {
    const value = structuredClone(artifact("javascript"));
    change(value);
    assert.throws(() => validateRuntimeArtifact(value, "javascript"));
  }
});

test("runtime results reject wrong root, pending commits, and sequence positions", () => {
  const expected = artifact("erlang");
  validateRuntimeResult(expected, root, expected.artifact.treePositions, 9);
  for (const change of [
    (value) => { value.artifact.root.title = "wrong"; },
    (value) => { value.artifact.pendingCount = 1; },
    (value) => { value.artifact.treePositions[4].indexInBatch = 5; },
    (value) => { value.artifact.sequenceNumber = 8; },
  ]) {
    const value = structuredClone(expected);
    change(value);
    assert.throws(() =>
      validateRuntimeResult(value, root, expected.artifact.treePositions, 9));
  }
});

test("coordinator rejects absent, empty, stale, wrong-target, and failed consumer output", async () => {
  const outputRoot = await mkdtemp(join(tmpdir(), "watershed-runtime-test-"));
  try {
    for (const failure of [
      "missing", "empty", "stale", "target", "consumer",
      "replay-missing", "replay-empty", "replay-stale",
    ]) {
      const produce = async (target, path) => {
        const replay = path.endsWith("-replay.json");
        if (failure === "missing" || (replay && failure === "replay-missing")) return;
        if (failure === "empty" || (replay && failure === "replay-empty")) {
          return writeFile(path, "");
        }
        const value = artifact(failure === "target" ? "javascript" : target);
        if (!replay) {
          value.artifact.pendingCount = 6;
          value.artifact.treePositions = [];
          value.artifact.root.point.x = 0;
        }
        if (failure === "stale") value.artifact.clientId = "old";
        if (replay && failure === "replay-stale") {
          value.artifact.outbound[0].contents = { type: "stale" };
        }
        return writeFile(path, JSON.stringify(value));
      };
      await assert.rejects(runRuntimeInterop({
        outputRoot, prepare: async () => ({ clientId: "native", input: {} }),
        produce,
        consume: async () => {
          if (failure === "consumer") throw new Error("upstream failed");
          return { root, treePositions: artifact("erlang").artifact.treePositions,
            sequenceNumber: 9 };
        },
      }), failure === "consumer" ? /upstream failed/ : /artifact|target|client|outbound/i);
      assert.deepEqual(await readdir(outputRoot), [], `unclean ${failure} run directory`);
    }
  } finally {
    await rm(outputRoot, { recursive: true, force: true });
  }
});
