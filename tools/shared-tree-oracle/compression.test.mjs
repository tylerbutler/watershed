import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { validateCompressionCapture } from "./compression.mjs";

const capture = JSON.parse(await readFile(new URL(
  "../../test/fixtures/shared_tree/compression.json",
  import.meta.url,
), "utf8"));

test("accepts the complete pinned compression capture", () => {
  assert.equal(validateCompressionCapture(capture), capture);
});

test("source hash is part of the captured contract", () => {
  const changed = structuredClone(capture);
  changed.upstream.commit = "0000000000000000000000000000000000000000";
  assert.throws(() => validateCompressionCapture(changed), /source|upstream|commit/i);
});

test("required producer cases are part of the captured contract", () => {
  const changed = structuredClone(capture);
  changed.cases = changed.cases.filter(({ id }) => id !== "default-chunked-group");
  assert.throws(() => validateCompressionCapture(changed), /default-chunked-group/);
});

test("measured chunk count is part of the captured contract", () => {
  const changed = structuredClone(capture);
  const target = changed.cases.find(({ id }) => id === "default-chunked-group");
  target.measurements.chunkCount += 1;
  assert.throws(() => validateCompressionCapture(changed), /chunk count/i);
});

test("default threshold is part of the captured contract", () => {
  const changed = structuredClone(capture);
  changed.defaults.minimumBatchSizeInBytes = 1;
  assert.throws(() => validateCompressionCapture(changed), /threshold/i);
});

test("required frame vectors are part of the captured contract", () => {
  const changed = structuredClone(capture);
  changed.frames = changed.frames.filter(({ id }) => id !== "overlapping-match");
  assert.throws(() => validateCompressionCapture(changed), /overlapping-match/);
});

test("bootstrap snapshot context is part of the captured contract", () => {
  const changed = structuredClone(capture);
  delete changed.probe.bootstrapSnapshot;
  assert.throws(() => validateCompressionCapture(changed), /bootstrap snapshot/i);
});

test("schema activation observations are part of the captured contract", () => {
  const changed = structuredClone(capture);
  delete changed.probe.schemaActivation;
  assert.throws(() => validateCompressionCapture(changed), /schema activation/i);
});
