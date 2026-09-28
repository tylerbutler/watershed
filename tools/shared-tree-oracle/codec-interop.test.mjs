import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

const reference = {
  package: "@fluidframework/tree",
  version: "3.1.0",
  commit: "c3c5bf0ecd313362e83fe8a02b7d39e7e0736960",
};

function artifact() {
  return {
    formatVersion: 1,
    reference: { ...reference },
    target: "erlang",
    items: [
      {
        id: "native-string",
        kind: "fieldBatch",
        encoded: {
          version: 2,
          identifiers: [],
          shapes: [{ c: { extraFields: 1 } }, { a: 0 }],
          data: [[1, ["com.fluidframework.leaf.string", true, "native", []]]],
        },
      },
    ],
  };
}

test("codec interop exposes a fail-closed coordinator", async () => {
  const module = await import("./codec-interop.mjs");
  assert.equal(typeof module.validateNativeArtifact, "function");
  assert.equal(typeof module.runCodecInterop, "function");
});

test("native codec artifact validation accepts a complete nonempty artifact", async () => {
  const { validateNativeArtifact } = await import("./codec-interop.mjs");
  assert.doesNotThrow(() => validateNativeArtifact(artifact()));
});

test("native codec artifact validation rejects stale, empty, duplicate, and incomplete data", async () => {
  const { validateNativeArtifact } = await import("./codec-interop.mjs");
  for (const mutate of [
    (value) => { value.formatVersion = 2; },
    (value) => { value.reference.commit = "other"; },
    (value) => { value.target = "native"; },
    (value) => { value.items = []; },
    (value) => { value.items.push(structuredClone(value.items[0])); },
    (value) => { value.items[0].kind = "unknown"; },
    (value) => { value.items[0].schemaProfile = "unknown"; },
    (value) => { delete value.items[0].encoded; },
  ]) {
    const value = artifact();
    mutate(value);
    assert.throws(() => validateNativeArtifact(value));
  }
});

test("message and summary artifacts require their explicit compressor context", async () => {
  const { validateNativeArtifact } = await import("./codec-interop.mjs");
  for (const kind of ["message", "summary"]) {
    const value = artifact();
    value.items[0] = {
      id: `native-${kind}`,
      kind,
      encoded: {},
      compressor: "serialized",
      compressorMode: "ongoing",
      session: "11111111-1111-4111-8111-111111111111",
    };
    if (kind === "message") {
      Object.assign(value.items[0], {
        initialSummary: {},
        allocationRanges: [],
        sequenceNumber: 1,
        referenceSequenceNumber: 0,
        minimumSequenceNumber: 0,
        indexInBatch: null,
      });
    }
    assert.doesNotThrow(() => validateNativeArtifact(value));
    delete value.items[0].compressor;
    assert.throws(() => validateNativeArtifact(value), /compressor/);
    value.items[0].compressor = "serialized";
    delete value.items[0].compressorMode;
    assert.throws(() => validateNativeArtifact(value), /compressorMode/);
  }
});

test("array message artifacts require sequence and graph evidence", async () => {
  const { validateNativeArtifact } = await import("./codec-interop.mjs");
  const value = artifact();
  value.items[0] = {
    id: "message-array-sequence",
    kind: "message",
    schemaProfile: "array",
    encoded: [{ version: 7 }],
    compressor: "serialized",
    compressorMode: "summary",
    session: "11111111-1111-4111-8111-111111111111",
    initialSummary: {},
    allocationRanges: [],
    sequencing: [{
      clientId: "client",
      clientSequenceNumber: 1,
      referenceSequenceNumber: 0,
      sequenceNumber: 1,
      minimumSequenceNumber: 0,
    }],
    expectedGraphs: [[]],
  };
  assert.doesNotThrow(() => validateNativeArtifact(value));
  for (const field of ["sequencing", "expectedGraphs"]) {
    const incomplete = structuredClone(value);
    delete incomplete.items[0][field];
    assert.throws(
      () => validateNativeArtifact(incomplete),
      new RegExp(field === "expectedGraphs" ? "expected graphs" : field),
    );
  }
  value.items[0].id = "message-array-advanced-nested";
  value.items[0].nativeGraphs = [[]];
  assert.doesNotThrow(() => validateNativeArtifact(value));
  delete value.items[0].nativeGraphs;
  assert.throws(() => validateNativeArtifact(value), /native graphs/);
});

test("codec interop produces and consumes fresh artifacts for both targets", async (t) => {
  const root = await mkdtemp(join(tmpdir(), "watershed-codec-interop-"));
  t.after(async () => {
    const { rm } = await import("node:fs/promises");
    await rm(root, { recursive: true, force: true });
  });
  const calls = [];
  const { runCodecInterop } = await import("./codec-interop.mjs");
  const result = await runCodecInterop({
    outputRoot: root,
    produce: async (target, output) => {
      calls.push(`produce:${target}`);
      const value = artifact();
      value.target = target;
      await writeFile(output, JSON.stringify(value));
    },
    consume: async (input, output) => {
      const value = JSON.parse(await readFile(input, "utf8"));
      calls.push(`consume:${value.target}`);
      await mkdir(output, { recursive: true });
      await writeFile(join(output, "codec-observations.json"), JSON.stringify({
        formatVersion: 1,
        reference,
        target: value.target,
        observations: [{
          id: "native-string",
          kind: "fieldBatch",
          fields: [[{
            type: "com.fluidframework.leaf.string",
            value: "native",
          }]],
        }],
      }));
    },
    expectedIds: ["native-string"],
    expected: null,
  });
  assert.deepEqual(calls, [
    "produce:erlang",
    "consume:erlang",
    "produce:javascript",
    "consume:javascript",
  ]);
  assert.equal(result.itemCount, 1);
  assert.equal(result.targetCount, 2);
});

test("codec interop rejects missing and divergent consumer observations", async (t) => {
  const root = await mkdtemp(join(tmpdir(), "watershed-codec-interop-"));
  t.after(async () => {
    const { rm } = await import("node:fs/promises");
    await rm(root, { recursive: true, force: true });
  });
  const { runCodecInterop } = await import("./codec-interop.mjs");
  await assert.rejects(
    runCodecInterop({
      outputRoot: root,
      produce: async (target, output) => {
        const value = artifact();
        value.target = target;
        await writeFile(output, JSON.stringify(value));
      },
      consume: async (input, output) => {
        const value = JSON.parse(await readFile(input, "utf8"));
        if (value.target === "erlang") {
          await mkdir(output, { recursive: true });
          await writeFile(join(output, "codec-observations.json"), JSON.stringify({
            formatVersion: 1,
            reference,
            target: value.target,
            observations: [],
          }));
        }
      },
      expectedIds: ["native-string"],
      expected: null,
    }),
  );

  await assert.rejects(
    runCodecInterop({
      outputRoot: root,
      produce: async (target, output) => {
        const value = artifact();
        value.target = target;
        await writeFile(output, JSON.stringify(value));
      },
      consume: async (input, output) => {
        const value = JSON.parse(await readFile(input, "utf8"));
        await mkdir(output, { recursive: true });
        await writeFile(join(output, "codec-observations.json"), JSON.stringify({
          formatVersion: 1,
          reference,
          target: value.target,
          observations: [{
            id: "native-string",
            kind: "fieldBatch",
            fields: value.target === "erlang" ? [] : [[{ type: "different" }]],
          }],
        }));
      },
      expectedIds: ["native-string"],
      expected: null,
    }),
    /target observations differ/,
  );
});

test("codec interop rejects summaries without detached and history evidence", async (t) => {
  const root = await mkdtemp(join(tmpdir(), "watershed-codec-summary-evidence-"));
  t.after(async () => {
    const { rm } = await import("node:fs/promises");
    await rm(root, { recursive: true, force: true });
  });
  const { runCodecInterop } = await import("./codec-interop.mjs");
  await assert.rejects(
    runCodecInterop({
      outputRoot: root,
      produce: async (target, output) => {
        const value = artifact();
        value.target = target;
        value.items[0] = {
          id: "summary",
          kind: "summary",
          encoded: {},
          compressor: "serialized",
          compressorMode: "summary",
          session: "11111111-1111-4111-8111-111111111111",
        };
        await writeFile(output, JSON.stringify(value));
      },
      consume: async (input, output) => {
        const value = JSON.parse(await readFile(input, "utf8"));
        await mkdir(output, { recursive: true });
        await writeFile(join(output, "codec-observations.json"), JSON.stringify({
          formatVersion: 1,
          reference,
          target: value.target,
          observations: [{
            id: "summary",
            kind: "summary",
            visible: null,
            continued: "upstream-continuation",
          }],
        }));
      },
      expectedIds: ["summary"],
      expected: null,
    }),
    /removed content/,
  );
});

test("array evidence rejects lost continuation, detached, peer, and refresher data", async () => {
  const { validateConsumerOutput } = await import("./codec-interop.mjs");
  const messageArtifact = {
    target: "erlang",
    items: [{
      id: "message-array-sequence",
      kind: "message",
      encoded: [{ version: 7 }],
    }],
  };
  const messageOutput = {
    formatVersion: 1,
    reference,
    target: "erlang",
    observations: [{
      id: "message-array-sequence",
      kind: "message",
      decoded: true,
      graphs: [[]],
      beforeApply: {},
      afterApply: {},
      continued: {
        rangeMoveIdentity: true,
        nestedEdit: "upstream-nested",
        visible: {},
      },
      continuation: {
        messages: [{ encoded: { version: 7 }, graphs: [{}] }, {
          encoded: { version: 7 },
          graphs: [{}],
        }],
        compressor: "serialized",
        session: "11111111-1111-4111-8111-111111111111",
      },
    }],
  };
  assert.doesNotThrow(() =>
    validateConsumerOutput(messageOutput, messageArtifact, ["message-array-sequence"]));
  const lostContinuation = structuredClone(messageOutput);
  lostContinuation.observations[0].continuation.messages = [];
  assert.throws(
    () => validateConsumerOutput(
      lostContinuation,
      messageArtifact,
      ["message-array-sequence"],
    ),
    /continuation wire evidence/,
  );

  const summaryArtifact = {
    target: "erlang",
    items: [{ id: "summary-array-peer-history", kind: "summary" }],
  };
  const dataChange = {
    type: "data",
    data: { fields: [], builds: [], refreshers: [{}] },
  };
  const summaryOutput = {
    formatVersion: 1,
    reference,
    target: "erlang",
    observations: [{
      id: "summary-array-peer-history",
      kind: "summary",
      rawInput: {
        schema: "source-schema",
        forest: "source-forest",
        compressor: "source-compressor",
      },
      emitted: {
        schema: "emitted-schema",
        forest: "emitted-forest",
        compressor: "emitted-compressor",
      },
      visible: { left: ["retained"] },
      removed: [{ major: "revision", minor: 1, tree: { value: "detached" } }],
      history: {
        trunk: [{ changes: [dataChange] }],
        peers: [{
          base: "root",
          commits: [{ changes: [dataChange] }],
        }],
      },
      restoredCompressor: "restored-compressor",
      continued: {
        rangeMoveIdentity: true,
        nestedEdit: "upstream-nested",
      },
    }],
  };
  assert.doesNotThrow(() =>
    validateConsumerOutput(
      summaryOutput,
      summaryArtifact,
      ["summary-array-peer-history"],
    ));
  for (const mutate of [
    (value) => { value.observations[0].history.peers[0].commits = []; },
    (value) => {
      value.observations[0].history.peers[0].commits[0].changes[0].data.refreshers = [];
    },
  ]) {
    const changed = structuredClone(summaryOutput);
    mutate(changed);
    assert.throws(
      () => validateConsumerOutput(
        changed,
        summaryArtifact,
        ["summary-array-peer-history"],
      ),
      /nonempty peer changes/,
    );
  }

  const detached = structuredClone(summaryOutput);
  detached.observations[0].id = "summary-array-retained-history";
  detached.observations[0].removed = [];
  summaryArtifact.items[0].id = "summary-array-retained-history";
  assert.throws(
    () => validateConsumerOutput(
      detached,
      summaryArtifact,
      ["summary-array-retained-history"],
    ),
    /detached content/,
  );

  const expectedSummary = structuredClone(summaryOutput.observations);
  delete expectedSummary[0].rawInput;
  delete expectedSummary[0].emitted;
  summaryArtifact.items[0].id = "summary-array-peer-history";
  for (const mutate of [
    (value) => {
      value.observations[0].history.peers[0].commits[0]
        .changes[0].data.refreshers[0] = { changed: true };
    },
    (value) => { value.observations[0].history.peers[0].base = "changed"; },
    (value) => {
      value.observations[0].history.peers[0].commits[0]
        .changes[0].data.fields = [{ changed: true }];
    },
    (value) => { value.observations[0].removed[0].tree.value = "changed"; },
    (value) => { value.observations[0].visible.left[0] = "changed"; },
  ]) {
    const changed = structuredClone(summaryOutput);
    mutate(changed);
    assert.throws(
      () => validateConsumerOutput(
        changed,
        summaryArtifact,
        ["summary-array-peer-history"],
        expectedSummary,
      ),
      /expected summary semantics/,
    );
  }
});
