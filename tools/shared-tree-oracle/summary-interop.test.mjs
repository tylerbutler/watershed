import assert from "node:assert/strict";
import { test } from "node:test";
import {
  runArtifactInterop, validateResults, validateSummaryArtifact,
} from "./summary-interop.mjs";

const implementations = ["upstream", "javascript", "erlang"];
const reference = {
  package: "@fluidframework/tree",
  version: "3.1.0",
  commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
};
const cells = implementations.flatMap((writer) =>
  implementations.map((reader) => ({
    writer, reader, writerVersion: `${writer}-commit`,
    snapshotSequenceNumber: 4,
    publicationSequenceNumber: 7,
    scenarioId: "summary-tail",
    loaded: true, continuedEditing: true, peerObservedEdit: true,
  })));

test("persistence matrix rejects omitted, duplicate, and unverified cells", () => {
  assert.equal(validateResults(cells).length, 9);
  for (const mutation of [
    (copy) => copy.pop(),
    (copy) => { copy[1] = structuredClone(copy[0]); },
    (copy) => { copy[2].peerObservedEdit = false; },
    (copy) => { copy[2].publicationSequenceNumber = 3; },
    (copy) => { copy[2].scenarioId = ""; },
  ]) {
    const copy = structuredClone(cells);
    mutation(copy);
    assert.throws(() => validateResults(copy));
  }
});

test("fresh summary artifacts require target, reference, cases and full hierarchy", () => {
  const artifact = {
    target: "javascript", reference, cases: [{
      id: "summary-tail", snapshotSequenceNumber: 7,
      publicationSequenceNumber: 7,
      tree: { type: "tree", entries: [[".metadata", {
        type: "blob", base64: "e30=",
      }]] },
    }],
  };
  validateSummaryArtifact(artifact, "javascript", ["summary-tail"]);
  for (const change of [
    (copy) => { copy.target = "erlang"; },
    (copy) => { copy.reference.commit = "stale"; },
    (copy) => { copy.cases = []; },
    (copy) => { copy.cases[0].tree.entries = []; },
    (copy) => { copy.cases[0].tree.entries[0][1].base64 = "@@"; },
  ]) {
    const copy = structuredClone(artifact);
    change(copy);
    assert.throws(() =>
      validateSummaryArtifact(copy, "javascript", ["summary-tail"]));
  }
});

test("artifact coordinator rejects missing and stale target output", async () => {
  await assert.rejects(
    runArtifactInterop({
      produce: async () => {},
      cases: ["summary-tail"],
    }),
    /Missing .* artifact/,
  );
});
