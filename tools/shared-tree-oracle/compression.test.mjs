import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { decompress } from "./node_modules/lz4js/lz4.js";
import { validateCompressionCapture } from "./compression.mjs";

const capture = JSON.parse(await readFile(new URL(
  "../../test/fixtures/shared_tree/compression.json",
  import.meta.url,
), "utf8"));
const profile = JSON.parse(await readFile(new URL(
  "../../test/fixtures/shared_tree/compression-profile.json",
  import.meta.url,
), "utf8"));
const caseById = (id) => capture.cases.find((entry) => entry.id === id);

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

test("allocation case contains a valid allocation before a real tree operation", () => {
  const entry = caseById("id-allocation-before-tree-use");
  const messages = entry.expected.flatMap((result) => result.messages);
  assert.deepEqual(messages.map((message) => message.type), [
    "idAllocation",
    "component",
  ]);
  const range = messages[0].contents;
  assert.equal(typeof range.sessionId, "string");
  assert.equal(range.ids.firstGenCount, 1);
  assert.ok(range.ids.count > 0);
  assert.ok(range.ids.requestedClusterSize > 0);
  assert.ok(range.ids.localIdRanges.length > 0);
  const treeOperation = messages[1].contents.contents.content.contents;
  assert.equal(typeof treeOperation.originatorId, "string");
  assert.ok(Array.isArray(treeOperation.changeset));
  assert.ok(JSON.stringify(treeOperation).includes(String(-range.ids.firstGenCount)));
});

test("decoded measurements equal the real decompressed input", () => {
  for (const id of [
    "default-compressed-singleton",
    "default-compressed-group",
    "id-allocation-before-tree-use",
  ]) {
    const entry = caseById(id);
    const decoded = decompress(Buffer.from(entry.messages[0].contents.packedContents, "base64"));
    assert.equal(entry.measurements.decodedBytes, decoded.byteLength, id);
  }
});

test("plain producer cases require nonempty messages and expected output", () => {
  const changed = structuredClone(capture);
  const target = changed.cases.find(({ id }) => id === "plain-singleton");
  target.messages = [];
  target.expected = [];
  assert.throws(() => validateCompressionCapture(changed), /plain-singleton/i);
});

test("case messages and expected outputs require object shapes", () => {
  const changed = structuredClone(capture);
  changed.cases.find(({ id }) => id === "plain-singleton").expected[0] = null;
  assert.throws(() => validateCompressionCapture(changed), /plain-singleton.*expected/i);
});

test("frame vectors must contain valid LZ4 bytes", () => {
  const changed = structuredClone(capture);
  changed.frames.find(({ id }) => id === "utf8").compressedBase64 = "AA==";
  assert.throws(() => validateCompressionCapture(changed), /utf8|lz4|frame/i);
});

test("frame flags require the complete observed shape", () => {
  const changed = structuredClone(capture);
  changed.frames.find(({ id }) => id === "utf8").flags = { blockCount: 1 };
  assert.throws(() => validateCompressionCapture(changed), /utf8|flags/i);
});

test("compressed case decoded measurements are verified against the frame", () => {
  const changed = structuredClone(capture);
  changed.cases.find(({ id }) => id === "default-compressed-group")
    .measurements.decodedBytes = 1;
  assert.throws(() => validateCompressionCapture(changed), /decoded byte/i);
});

test("bootstrap observations require non-null metadata and chunks blobs", () => {
  const changed = structuredClone(capture);
  changed.probe.bootstrapSnapshot.rootBlobs[".metadata"] = null;
  changed.probe.bootstrapSnapshot.rootBlobs[".chunks"] = null;
  assert.throws(() => validateCompressionCapture(changed), /bootstrap|blob/i);
});

test("negative frame observations are required", () => {
  const changed = structuredClone(capture);
  delete changed.cases.find(({ id }) => id === "malformed-frame").upstreamObservation;
  assert.throws(() => validateCompressionCapture(changed), /malformed-frame|observation/i);
});

test("post-activation operation is a sequenced continuation of activation", () => {
  const activation = caseById("schema-activation");
  const operation = caseById("post-activation-compressed-operation");
  assert.equal(operation.activation.caseId, activation.id);
  assert.equal(operation.activation.sequenceNumber, activation.messages[0].sequenceNumber);
  assert.equal(operation.activation.schemaRefSeq, activation.expected[0].refSeq);
  assert.ok(operation.messages[0].sequenceNumber > operation.activation.sequenceNumber);
  assert.ok(operation.messages[0].referenceSequenceNumber >= operation.activation.schemaRefSeq);
});

test("generated profile records both owned probe identities", () => {
  assert.equal(profile.probe.path, capture.probe.path);
  assert.equal(profile.probe.sha256, capture.probe.digest);
  assert.equal(profile.probe.treePath, capture.probe.treePath);
  assert.equal(profile.probe.treeSha256, capture.probe.treeDigest);
});
