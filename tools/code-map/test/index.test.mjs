import test from "node:test";
import assert from "node:assert/strict";
import { refreshIndex } from "../lib/index.mjs";
import { makeRepo, write, git, fs, join } from "./helpers.mjs";

const names = (index) => index.files.flatMap((file) => file.symbols.map((s) => s.name));

test("refresh detects same-mtime edits, renames, additions, and deletions", async (t) => {
  const root = await makeRepo(t, { "src/a.ts": "function alpha() {}\n" });
  git(root, "add", ".");
  assert.deepEqual(names(await refreshIndex(root)), ["alpha"]);
  const path = join(root, "src/a.ts");
  const stat = await fs.stat(path);
  await fs.writeFile(path, "function bravo() {}\n");
  await fs.utimes(path, stat.atime, stat.mtime);
  assert.deepEqual(names(await refreshIndex(root)), ["bravo"]);
  await fs.rename(path, join(root, "renamed.ts"));
  await write(root, "added.gleam", "pub fn added() { Nil }");
  const next = await refreshIndex(root);
  assert.deepEqual(names(next), ["added", "bravo"]);
  assert.equal(next.files.some((f) => f.path === "src/a.ts"), false);
});

test("no-op refresh is deterministic and does not rewrite the cache", async (t) => {
  const root = await makeRepo(t, { "a.ts": "function a() {}" });
  const first = await refreshIndex(root);
  const cache = join(root, ".code-map/index.json");
  const before = await fs.stat(cache, { bigint: true });
  assert.deepEqual(await refreshIndex(root), first);
  assert.equal((await fs.stat(cache, { bigint: true })).mtimeNs, before.mtimeNs);
  assert.equal(first.files.some((f) => f.path.startsWith(".code-map/")), false);
});

test("parse errors discard stale symbols, preserve healthy files and recover", async (t) => {
  const root = await makeRepo(t, { "a.ts": "function a() {}", "b.ts": "function b() {}" });
  await refreshIndex(root);
  await write(root, "a.ts", "function bad(");
  const broken = await refreshIndex(root);
  assert.deepEqual(names(broken), ["b"]);
  assert.equal(broken.complete, false);
  assert.equal(broken.files[0].status, "parse-error");
  await write(root, "a.ts", "function fixed() {}");
  assert.deepEqual(names(await refreshIndex(root)), ["fixed", "b"]);
});

test("configuration changes invalidate cached classification without source edits", async (t) => {
  const root = await makeRepo(t, { "vendor/a.ts": "function a() {}" });
  const before = await refreshIndex(root);
  assert.deepEqual(names(before), ["a"]);
  await write(root, "code-map.json", JSON.stringify({ version: 1, excludePaths: ["vendor"] }));
  const excluded = await refreshIndex(root);
  assert.deepEqual(names(excluded), []);
  assert.notEqual(before.configHash, excluded.configHash);
  await fs.unlink(join(root, "code-map.json"));
  assert.deepEqual(names(await refreshIndex(root)), ["a"]);
});

test("tool version changes force reparsing even when cached source hashes match", async (t) => {
  const root = await makeRepo(t, { "a.ts": "function actual() {}" });
  const index = await refreshIndex(root);
  index.toolHash = "0".repeat(64);
  index.files[0].symbols = [];
  await fs.writeFile(join(root, ".code-map/index.json"), JSON.stringify(index));
  assert.deepEqual(names(await refreshIndex(root)), ["actual"]);
});

test("corrupt and malformed caches require explicit rebuild", async (t) => {
  const root = await makeRepo(t, { "a.ts": "function a() {}" });
  const first = await refreshIndex(root);
  const cache = join(root, ".code-map/index.json");
  for (const content of ["{", JSON.stringify({ version: 9 }), JSON.stringify({ ...first, files: [{ path: "a.ts" }] })]) {
    await fs.writeFile(cache, content);
    await assert.rejects(refreshIndex(root), /refresh --rebuild/);
    assert.equal(await fs.readFile(cache, "utf8"), content);
    assert.deepEqual(names(await refreshIndex(root, { rebuild: true })), ["a"]);
  }
});

test("fatal config errors preserve previous cache and cache symlinks are refused", async (t) => {
  const root = await makeRepo(t, { "a.ts": "function a() {}" });
  await refreshIndex(root);
  const cache = join(root, ".code-map/index.json");
  const before = await fs.readFile(cache, "utf8");
  await write(root, "code-map.json", "{");
  await assert.rejects(refreshIndex(root), /config/i);
  assert.equal(await fs.readFile(cache, "utf8"), before);
  await fs.unlink(join(root, "code-map.json"));
  await fs.rename(cache, join(root, "other.json"));
  await fs.symlink("../other.json", cache);
  await assert.rejects(refreshIndex(root), /symlink/i);
});

test("writer failure preserves cache and cleans up its unique temporary file", async (t) => {
  const root = await makeRepo(t, { "a.ts": "function a() {}" });
  await refreshIndex(root);
  const cache = join(root, ".code-map/index.json");
  const before = await fs.readFile(cache, "utf8");
  await write(root, "a.ts", "function newer() {}");
  t.mock.method(fs, "rename", async () => { throw Object.assign(new Error("write denied"), { code: "EACCES" }); });
  await assert.rejects(refreshIndex(root), /write denied/);
  t.mock.restoreAll();
  assert.equal(await fs.readFile(cache, "utf8"), before);
  assert.deepEqual(await fs.readdir(join(root, ".code-map")), ["index.json"]);
});
