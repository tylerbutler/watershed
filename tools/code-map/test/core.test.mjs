import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const baseline = JSON.parse(await readFile(new URL("./fixtures/contracts.json", import.meta.url), "utf8"));

test("typed core round-trips legacy indexes into native JavaScript objects", async () => {
  const { core } = await import("../lib/core.mjs");
  const output = core().encode_index(core().decode_index(baseline.index));
  assert.deepEqual(output, baseline.index);
  assert.equal(Object.getPrototypeOf(output), Object.prototype);
  assert.ok(Array.isArray(output.files));
  assert.throws(() => core().decode_index({ ...baseline.index, version: 99 }), /cache/i);
});

test("typed cache boundary rejects unsafe positions and inconsistent identities", async () => {
  const { core } = await import("../lib/core.mjs");
  for (const change of [
    (index) => { index.files.push(index.files[0]); },
    (index) => { index.files.find((f) => f.symbols.length).symbols[0].range.start.line = 2 ** 54; },
    (index) => { index.files.find((f) => f.symbols.length).symbols[0].id = "incorrect"; },
    (index) => { index.complete = false; },
  ]) {
    const index = structuredClone(baseline.index);
    change(index);
    assert.throws(() => core().decode_index(index), /cache/i);
  }
});
