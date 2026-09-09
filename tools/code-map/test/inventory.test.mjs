import test from "node:test";
import assert from "node:assert/strict";
import { discoverFiles } from "../lib/inventory.mjs";
import { validateConfig } from "../lib/config.mjs";
import { makeRepo, write, git, fs, join } from "./helpers.mjs";

test("inventory includes tracked and untracked files but omits ignored artifacts and cache", async (t) => {
  const root = await makeRepo(t, {
    ".gitignore": "ignored/\n*.png\n", "src/a.ts": "function a() {}",
    "build/useful.ts": "function useful() {}", "tracked.png": "image",
  });
  git(root, "add", "src/a.ts");
  git(root, "add", "-f", "tracked.png");
  await write(root, "ignored/a.ts", "function ignored() {}");
  await write(root, ".code-map/index.json", "{}");
  await write(root, "src/space é\nname.ts", "function unique() {}");
  const files = await discoverFiles(root, validateConfig({ version: 1 }));
  assert.deepEqual(files.map((f) => f.path), [".gitignore", "build/useful.ts", "src/a.ts", "src/space é\nname.ts", "tracked.png"]);
  assert.equal(files.find((f) => f.path === "build/useful.ts").status, "pending");
  assert.equal(files.find((f) => f.path === "tracked.png").status, "unsupported");
});

test("exclusions match directory components and exact path boundaries", async (t) => {
  const root = await makeRepo(t, {
    "build/a.ts": "", "rebuild/a.ts": "", "vendor/a.ts": "", "vendorish/a.ts": "",
    "nested/build/a.ts": "", "readme.md": "",
  });
  const files = await discoverFiles(root, validateConfig({ version: 1, excludeDirs: ["build"], excludePaths: ["vendor"] }));
  assert.deepEqual(files.filter((f) => f.status === "excluded").map((f) => f.path), ["build/a.ts", "nested/build/a.ts", "vendor/a.ts"]);
});

test("deleted paths vanish and symlinked ancestors are never followed", async (t) => {
  const root = await makeRepo(t, { "src/a.ts": "function a() {}", "gone.ts": "" });
  git(root, "add", ".");
  await fs.unlink(join(root, "gone.ts"));
  await fs.rename(join(root, "src"), join(root, "other"));
  await fs.symlink("other", join(root, "src"));
  const files = await discoverFiles(root, validateConfig({ version: 1 }));
  assert.equal(files.some((f) => f.path === "gone.ts"), false);
  assert.equal(files.find((f) => f.path === "src/a.ts").status, "excluded");
});

test("invalid UTF-8 is visible rather than parsed with replacement characters", async (t) => {
  const root = await makeRepo(t, { "a.ts": Buffer.from([0xff]) });
  const [file] = await discoverFiles(root, validateConfig({ version: 1 }));
  assert.equal(file.status, "unreadable");
  assert.match(file.diagnostics[0].message, /UTF-8/);
});

test("unreadable metadata retains the source language", async (t) => {
  const root = await makeRepo(t, { "a.ts": "function a() {}" });
  const original = fs.lstat;
  t.mock.method(fs, "lstat", async (path, ...args) => {
    if (path === join(root, "a.ts")) throw Object.assign(new Error("denied"), { code: "EACCES" });
    return original(path, ...args);
  });
  const [file] = await discoverFiles(root, validateConfig({ version: 1 }));
  assert.equal(file.status, "unreadable");
  assert.equal(file.language, "typescript");
});
