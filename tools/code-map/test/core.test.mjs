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

test("typed configuration preserves absent fields and rejects null and unknown fields", async () => {
  const { core } = await import("../lib/core.mjs");
  assert.deepEqual(core().normalize_config({ version: 1, excludeDirs: undefined }), {
    version: 1, excludeDirs: [], excludePaths: [],
  });

  for (const config of [
    { version: 1, excludePaths: null },
    { version: 1, excludeDirs: ["a", "a"] },
    { version: 1, unknown: true },
  ]) assert.throws(() => core().normalize_config(config), /config/i);
});

test("Gleam normalizes raw parser declarations and rejects malformed kinds", async () => {
  const { core } = await import("../lib/core.mjs");
  const file = baseline.index.files.find((f) => f.path === "src/a.ts");
  const raw = { symbols: file.symbols.map(({ id, qualifiedName, ...symbol }) => symbol),
    diagnostics: [], skippedRegions: [] };
  assert.deepEqual(core().normalize_parse(file.path, raw).symbols, file.symbols);
  raw.symbols[0].kind = "typo";
  assert.throws(() => core().normalize_parse(file.path, raw), /parser/i);
});

test("Gleam queries remain synchronous and preserve every baseline view", async () => {
  const { core } = await import("../lib/core.mjs");
  for (const { request, view, text } of baseline.views) {
    const actual = core().query_index(baseline.index, request);
    assert.equal(actual instanceof Promise, false);
    assert.deepEqual(actual, view);
    assert.equal(core().render_text(actual), text);
  }
  for (const request of [
    { command: "find", query: "a", limit: 2 ** 54 },
    { command: "overview", limit: 1 },
    { command: "files", path: null },
  ]) assert.throws(() => core().query_index(baseline.index, request));
});

test("typed refresh reuses successful files and rejects unexpected parser results", async () => {
  const { core } = await import("../lib/core.mjs");
  const prior = baseline.index;
  const candidates = prior.files.map((file) => file.status === "indexed"
    ? { ...file, status: "pending", symbols: [] } : file);
  const previous = core().decode_previous(prior);
  const plan = core().prepare_refresh(previous, candidates, prior.toolHash, prior.configHash);
  assert.deepEqual(core().parse_jobs(plan), []);
  assert.deepEqual(core().finish_refresh(plan, []), prior);
  assert.throws(() => core().finish_refresh(plan, [{
    path: "unexpected.ts", result: { symbols: [], diagnostics: [], skippedRegions: [] },
  }]), /refresh/i);
  const changed = core().prepare_refresh(previous, candidates, "f".repeat(64), prior.configHash);
  assert.equal(core().parse_jobs(changed).length, 4);
  assert.throws(() => core().finish_refresh(changed, []), /refresh/i);
});
