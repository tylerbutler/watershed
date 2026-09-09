import test from "node:test";
import assert from "node:assert/strict";
import { loadConfig, validateConfig, configHash } from "../lib/config.mjs";
import { makeRepo, write } from "./helpers.mjs";

test("missing config uses generic defaults, not consumer policy", async (t) => {
  const root = await makeRepo(t);
  assert.deepEqual(await loadConfig(root), { version: 1, excludeDirs: [], excludePaths: [] });
});

test("config validates version, fields and exclusion paths", () => {
  for (const input of [
    null, [], {}, { version: 2 }, { version: 1, typo: true },
    { version: 1, excludeDirs: ["a/b"] }, { version: 1, excludeDirs: [".."] },
    { version: 1, excludePaths: ["../a"] }, { version: 1, excludePaths: ["/a"] },
    { version: 1, excludePaths: ["a\\b"] }, { version: 1, excludePaths: ["a", "a"] },
  ]) assert.throws(() => validateConfig(input), /config/i);
  assert.deepEqual(validateConfig({ version: 1 }), { version: 1, excludeDirs: [], excludePaths: [] });
});

test("malformed config is not silently replaced with defaults", async (t) => {
  const root = await makeRepo(t, { "code-map.json": "{" });
  await assert.rejects(loadConfig(root), /code-map.json/);
  await write(root, "code-map.json", JSON.stringify({ version: 1, excludeDirs: ["z", "a"] }));
  const a = await loadConfig(root);
  assert.equal(configHash(a), configHash({ version: 1, excludeDirs: ["a", "z"], excludePaths: [] }));
});
