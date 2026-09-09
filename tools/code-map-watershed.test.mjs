import test, { before } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { lstat, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { refreshIndex, queryIndex } from "./code-map/lib/index.mjs";

const root = fileURLToPath(new URL("..", import.meta.url));
let index;
before(async () => { index = await refreshIndex(root); });

test("Watershed inventory accounts for current Git paths and supported source coverage", async () => {
  const candidates = new Set(execFileSync("git", [
    "-C", root, "ls-files", "--cached", "--others", "--exclude-standard", "--deduplicate", "-z",
  ], { encoding: "utf8" }).split("\0").filter((p) => p && p !== ".code-map" && !p.startsWith(".code-map/")));
  for (const path of candidates) {
    try { await lstat(join(root, path)); }
    catch (error) {
      if (error.code !== "ENOENT" && error.code !== "ENOTDIR") throw error;
      candidates.delete(path);
    }
  }
  assert.deepEqual(new Set(index.files.map((f) => f.path)), candidates);
  assert.equal(index.complete, true, JSON.stringify(index.files.filter((f) => f.diagnostics.length)));
  const config = JSON.parse(await readFile(join(root, "code-map.json"), "utf8"));
  for (const file of index.files) {
    const excluded = config.excludePaths.some((p) => file.path === p || file.path.startsWith(`${p}/`))
      || file.path.split("/").slice(0, -1).some((p) => config.excludeDirs.includes(p));
    if (excluded) {
      assert.equal(file.status, "excluded", file.path);
      assert.match(file.reason, /^Config exclusion:/);
    }
  }
  assert.ok(index.files.some((f) => f.language === "gleam" && f.status === "indexed"));
  assert.ok(index.files.some((f) => f.language === "astro" && f.status === "indexed"));
  assert.ok(index.files.some((f) => f.path.startsWith("tools/compile-fail/") && f.status === "indexed"));
});

for (const [path, name] of [
  ["src/watershed/p2p.gleam", "pn_counter_root"],
  ["src/watershed/transport_ffi.mjs", "connect"],
  ["src/watershed/transport_ffi.mjs", "utf8"],
  ["website/src/lib/snippet.ts", "sourceSnippet"],
  ["website/src/components/Architecture.astro", "wave"],
]) {
  test(`discovers ${name} at its original source location`, async () => {
    const view = queryIndex(index, { command: "find", query: name, path });
    const symbol = view.items.find((s) => s.name === name && s.path === path);
    assert.ok(symbol);
    const bytes = await readFile(join(root, path));
    const declaration = bytes.subarray(symbol.range.start.byte, symbol.range.end.byte).toString("utf8");
    assert.ok(declaration.includes(name));
    const prefix = bytes.subarray(0, symbol.range.start.byte).toString("utf8");
    assert.equal(symbol.range.start.line, prefix.split("\n").length);
    if (name === "utf8") assert.equal(symbol.exported, false);
  });
}

test("the just wrapper emits one JSON document without build output", () => {
  const output = execFileSync("just", ["code-map", "find", "pn_counter_root", "--limit", "1", "--json"], {
    cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"],
  });
  const view = JSON.parse(output);
  assert.equal(view.items.length, 1);
  assert.equal(view.items[0].name, "pn_counter_root");
});
