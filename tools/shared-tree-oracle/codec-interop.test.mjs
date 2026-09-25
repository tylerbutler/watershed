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
