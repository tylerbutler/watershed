import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  captureSummaryFoundations,
  validateSummaryFoundationsCase,
} from "./summary-foundations.mjs";

const fixtureRoot = new URL("../../test/fixtures/shared_tree/cases/", import.meta.url);
const originalCaseNames = [
  "bootstrap-map-handles",
  "batched-commits",
  "reconnect-before-ack",
  "summary-tail",
  "summary-writer-matrix",
];

async function fixture(name) {
  return JSON.parse(await readFile(new URL(`${name}.json`, fixtureRoot), "utf8"));
}

function originalCases() {
  return Promise.all(originalCaseNames.map(fixture));
}

test("summary foundations use the pinned upload manager for bytes and references", async () => {
  const existingCases = await originalCases();
  const unchanged = structuredClone(existingCases);
  const value = await captureSummaryFoundations(existingCases);
  const snapshot = existingCases.find(({ id }) => id === "summary-tail")
    .input.replayInput.snapshotAtS;
  const schemaTree =
    snapshot.tree.trees[".channels"].trees.A.trees[".channels"].trees._C
      .trees.indexes.trees.Schema;
  const schemaBlob = schemaTree.blobs.SchemaString;

  assert.equal(value.formatVersion, 1);
  assert.deepEqual(value.reference, {
    package: "@fluidframework/tree",
    version: "3.1.0",
    commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
  });
  assert.equal(value.id, "summary-foundations");
  assert.equal(value.domain, "summary");
  assert.equal(value.input.service, "SummaryTreeUploadManager");
  assert.deepEqual(existingCases, unchanged);
  assert.doesNotThrow(() => validateSummaryFoundationsCase(value));
  assert.equal(value.input.previousSnapshot.tree.id, snapshot.tree.id);
  assert.deepEqual(
    value.input.scenarios.map(({ label }) => label),
    [
      "snapshot-entries",
      "emitted-entries",
      "missing-parent",
      "missing-path",
      "wrong-kind",
      "malformed-percent-encoding",
    ],
  );

  const snapshotEntries = value.expected.observations.find(
    ({ label }) => label === "snapshot-entries",
  );
  assert(snapshotEntries);
  assert(
    snapshotEntries.entries.some(
      ({ components, kind }) =>
        components.join("/") === ".protocol" && kind === "tree",
    ),
  );
  assert(
    snapshotEntries.entries.some(
      ({ components, kind, bytes }) =>
        components.at(-1) === ".metadata"
        && kind === "blob"
        && typeof bytes === "string",
    ),
  );

  const emitted = value.expected.observations.find(
    ({ label }) => label === "emitted-entries",
  );
  assert(emitted);
  assert.deepEqual(
    emitted.entries.map(({ components, kind }) => [components, kind]),
    [
      [["binary"], "blob"],
      [["empty"], "blob"],
      [["text"], "blob"],
      [["plus+cash$"], "blob"],
      [["slash/name"], "tree"],
      [["slash/name", "nested"], "blob"],
      [["schema-copy"], "tree"],
      [["schema-string-copy"], "blob"],
      [["schema-string-copy-again"], "blob"],
      [["root-copy"], "tree"],
    ],
  );
  assert.equal(
    emitted.entries.find(({ components }) => components[0] === "binary").bytes,
    "AP+A",
  );
  assert.equal(
    emitted.entries.find(({ components }) => components[0] === "empty").bytes,
    "",
  );
  assert.equal(
    emitted.entries.find(({ components }) => components[0] === "text").bytes,
    Buffer.from("héllo", "utf8").toString("base64"),
  );
  assert.equal(
    emitted.entries.find(({ components }) => components[0] === "plus+cash$")
      .encodedName,
    "plus%2Bcash%24",
  );
  assert.equal(
    emitted.entries.find(({ components }) => components[0] === "slash/name")
      .encodedName,
    "slash%2Fname",
  );
  assert.equal(
    emitted.entries.find(({ components }) => components[0] === "schema-copy")
      .storageId,
    schemaTree.id,
  );
  assert.equal(
    emitted.entries.find(
      ({ components }) => components[0] === "schema-string-copy",
    ).storageId,
    schemaBlob,
  );
  assert.equal(
    emitted.entries.find(
      ({ components }) => components[0] === "schema-string-copy-again",
    ).storageId,
    schemaBlob,
  );
  assert.equal(
    emitted.entries.find(({ components }) => components[0] === "root-copy")
      .storageId,
    snapshot.tree.id,
  );

  assert.deepEqual(
    value.expected.observations
      .filter(({ refused }) => refused)
      .map(({ label }) => label),
    [
      "missing-parent",
      "missing-path",
      "wrong-kind",
      "malformed-percent-encoding",
    ],
  );
  assert(
    value.raw.blobs.some(
      ({ bytes, encoding }) => bytes === "AP+A" && encoding === "base64",
    ),
  );
  assert(
    value.raw.blobs.some(
      ({ bytes, encoding }) =>
        bytes === Buffer.from("héllo", "utf8").toString("base64")
        && encoding === "utf-8",
    ),
  );
  assert(
    value.raw.trees.some(({ entries }) =>
      entries.some(
        ({ path, mode, type }) =>
          path === "slash%2Fname" && mode === "040000" && type === "tree",
      )),
  );
});

test("summary foundations validation requires complete paired evidence", async () => {
  const value = await captureSummaryFoundations(await originalCases());

  for (const [message, mutate] of [
    ["keys", (copy) => { copy.extra = true; }],
    ["service", (copy) => { copy.input.service = "LocalDeltaConnectionServer"; }],
    ["scenarios", (copy) => { copy.input.scenarios.pop(); }],
    ["observations", (copy) => { copy.expected.observations.pop(); }],
    ["raw trees", (copy) => { copy.raw.trees = []; }],
    ["blob bytes", (copy) => { copy.raw.blobs[0].bytes = "AQID"; }],
    ["raw blobs", (copy) => { copy.raw.blobs.push(structuredClone(copy.raw.blobs[0])); }],
    ["refusals", (copy) => { copy.raw.refusals.pop(); }],
    ["refusal writes", (copy) => {
      copy.raw.refusals[0].blobs.push(structuredClone(copy.raw.blobs[0]));
    }],
    ["emitted entries", (copy) => {
      copy.raw.trees.find(({ sha }) => sha === copy.raw.rootId).entries[0].path =
        "renamed";
      copy.expected.observations[1].entries[0].components = ["renamed"];
      copy.expected.observations[1].entries[0].encodedName = "renamed";
    }],
    ["object reference", (copy) => {
      copy.raw.trees.find(({ sha }) => sha === copy.raw.rootId).entries[0].sha =
        "unknown-object";
      copy.expected.observations[1].entries[0].storageId = "unknown-object";
      copy.expected.observations[1].entries[0].bytes = undefined;
    }],
    ["refusal message", (copy) => {
      copy.expected.observations[2].refused = "different";
    }],
  ]) {
    const copy = structuredClone(value);
    mutate(copy);
    assert.throws(() => validateSummaryFoundationsCase(copy), new RegExp(message, "i"));
  }
});
