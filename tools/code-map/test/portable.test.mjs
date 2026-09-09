import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { relative } from "node:path";
import { refreshIndex } from "../lib/index.mjs";
import { temporary, makeRepo, write, fs, join, toolRoot } from "./helpers.mjs";

test("a relocated tool indexes unrelated sources without their project toolchains", async (t) => {
  const temporaryRoot = await temporary(t);
  const relocated = join(temporaryRoot, "standalone");
  const cwd = join(temporaryRoot, "invocation");
  await fs.mkdir(cwd);
  await fs.mkdir(relocated);
  for (const path of [
    "cli.mjs", "lib", "src", "package.json", "gleam.toml", "manifest.toml",
    "pnpm-lock.yaml", "build/dev/javascript", "node_modules",
  ]) {
    await fs.cp(join(toolRoot, path), join(relocated, path), { recursive: true, verbatimSymlinks: true });
  }
  const canonicalRoot = await fs.realpath(relocated);
  async function inspectLinks(path) {
    for (const item of await fs.readdir(path, { withFileTypes: true })) {
      const full = join(path, item.name);
      if (item.isSymbolicLink()) {
        const destination = await fs.realpath(full);
        assert.ok(!relative(canonicalRoot, destination).startsWith(".."), `Escaping dependency: ${full}`);
      } else if (item.isDirectory()) await inspectLinks(full);
    }
  }
  await inspectLinks(relocated);
  const target = await makeRepo(t, {
    "hello.gleam": "pub fn hello() { Nil }",
    "hello.js": "function hello() {}",
    "hello.ts": "function hello(): void {}",
    "hello.astro": "---\nfunction hello() {}\n---\n<p>Example</p>",
  });
  const result = spawnSync(process.execPath, [
    join(relocated, "cli.mjs"), "--root", target, "find", "hello", "--json",
  ], { cwd, encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
  const view = JSON.parse(result.stdout);
  assert.equal(view.total, 4);
  assert.equal(view.complete, true);
  assert.deepEqual(await fs.readdir(cwd), []);
  await assert.rejects(fs.stat(join(relocated, ".code-map")), { code: "ENOENT" });
  const movedLibrary = await import(pathToFileURL(join(relocated, "lib/index.mjs")));
  const original = await refreshIndex(target);
  const moved = await movedLibrary.refreshIndex(target, { rebuild: true });
  assert.deepEqual(moved.files.map((f) => f.symbols.map((s) => s.id)), original.files.map((f) => f.symbols.map((s) => s.id)));
  await fs.rename(join(relocated, "build"), join(relocated, "unbuilt"));
  const unbuilt = spawnSync(process.execPath, [
    join(relocated, "cli.mjs"), "--root", target, "overview", "--json",
  ], { cwd, encoding: "utf8" });
  assert.equal(unbuilt.status, 1);
  assert.equal(unbuilt.stdout, "");
  assert.match(unbuilt.stderr, /pnpm run build/);
});

test("library calls keep configuration and cached symbols isolated by target repository", async (t) => {
  const a = await makeRepo(t, { "build/a.ts": "function alpha() {}" });
  const b = await makeRepo(t, { "build/b.ts": "function bravo() {}",
    "code-map.json": JSON.stringify({ version: 1, excludeDirs: ["build"] }) });
  assert.equal((await refreshIndex(a)).files.find((f) => f.path === "build/a.ts").symbols[0].name, "alpha");
  assert.equal((await refreshIndex(b)).files.find((f) => f.path === "build/b.ts").status, "excluded");
  await write(a, "build/a.ts", "function changed() {}");
  assert.equal((await refreshIndex(a)).files.find((f) => f.path === "build/a.ts").symbols[0].name, "changed");
  assert.equal((await refreshIndex(b)).files.find((f) => f.path === "build/b.ts").symbols.length, 0);
});
