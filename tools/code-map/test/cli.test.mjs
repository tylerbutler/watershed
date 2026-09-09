import test from "node:test";
import assert from "node:assert/strict";
import { makeRepo, temporary, write, runCli, join, fs, cli } from "./helpers.mjs";
import { spawnSync } from "node:child_process";
import { queryIndex } from "../lib/queries.mjs";

const sample = {
  "src/a.ts": "export function connect() {}\nfunction connector() {}\nfunction disconnect() {}",
  "src/b.gleam": "pub fn connect() { Nil }",
  "srcish/a.ts": "function connect() {}",
  "notes.md": "# Notes",
};

test("CLI searches literal names with deterministic ranking and explicit pagination", async (t) => {
  const root = await makeRepo(t, sample);
  const result = runCli(root, ["find", "CONNECT", "--path", "src", "--limit", "2", "--json"]);
  assert.equal(result.status, 0, result.stderr);
  const view = JSON.parse(result.stdout);
  assert.deepEqual(view.items.map((s) => s.name), ["connect", "connect"]);
  assert.equal(view.total, 4);
  assert.equal(view.hasMore, true);
  const next = runCli(root, ["find", "connect", "--path", "src", "--offset", "2", "--json"]);
  assert.deepEqual(JSON.parse(next.stdout).items.map((s) => s.name), ["connector", "disconnect"]);
});

test("overview, files, file, refresh, and no-match results are machine readable", async (t) => {
  const root = await makeRepo(t, sample);
  for (const args of [[], ["files"], ["file", "src/a.ts"], ["file", "notes.md"], ["refresh"], ["refresh", "--rebuild"], ["find", "missing"]]) {
    const result = runCli(root, [...args, "--json"]);
    assert.equal(result.status, 0, result.stderr);
    const view = JSON.parse(result.stdout);
    assert.equal(view.complete, true);
    assert.ok(view.coverage.limits.length > 0);
  }
  const unsupported = JSON.parse(runCli(root, ["file", "notes.md", "--json"]).stdout);
  assert.equal(unsupported.file.status, "unsupported");
  assert.equal(unsupported.total, 0);
});

test("CLI selects an unrelated repository from a non-Git cwd", async (t) => {
  const root = await makeRepo(t, sample);
  const cwd = await temporary(t);
  const result = runCli(cwd, ["--root", join(root, "src"), "find", "connect", "--json"]);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(JSON.parse(result.stdout).total, 5);
  await assert.rejects(fs.stat(join(cwd, ".code-map")), { code: "ENOENT" });
});

test("CLI rejects invalid options, paths and subcommand combinations", async (t) => {
  const root = await makeRepo(t, sample);
  for (const args of [
    ["unknown"], ["find"], ["find", "a", "--limit", "0"], ["find", "a", "--offset", "-1"],
    ["find", "a", "--kind", "typo"], ["find", "a", "--path", "../outside"],
    ["file", "/etc/passwd"], ["file", "missing.ts"], ["overview", "--limit", "1"],
    ["files", "--rebuild"], ["find", "a", "--typo"], ["file", "src/a.ts", "extra"],
  ]) {
    const result = runCli(root, args);
    assert.equal(result.status, 1, args.join(" "));
    assert.equal(result.stdout, "", args.join(" "));
    assert.match(result.stderr, /error:/);
  }
});

test("syntax errors produce incomplete JSON and status 2, not stale declarations", async (t) => {
  const root = await makeRepo(t, sample);
  assert.equal(runCli(root, ["refresh"]).status, 0);
  await write(root, "src/a.ts", "function bad(");
  const result = runCli(root, ["find", "connect", "--json"]);
  assert.equal(result.status, 2, result.stderr);
  const view = JSON.parse(result.stdout);
  assert.equal(view.complete, false);
  assert.equal(view.total, 2);
  assert.ok(view.diagnostics.length > 0);
  assert.equal(view.items.some((s) => s.path === "src/a.ts"), false);
});

test("text views expose truncation and escape control characters in paths", async (t) => {
  const root = await makeRepo(t, { ...sample, "src/control\u001b.ts": "function found() {}" });
  const result = runCli(root, ["files", "--limit", "1"]);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /--offset 1/);
  const all = runCli(root, ["files"]);
  assert.equal(all.stdout.includes("\u001b"), false);
  assert.match(all.stdout, /\\u001b/);
});

test("importing CLI or library does not index, print, or exit", async (t) => {
  const cwd = await temporary(t);
  const result = spawnSync(process.execPath, ["--input-type=module", "-e",
    `await import(${JSON.stringify(new URL("../lib/index.mjs", import.meta.url).href)}); await import(${JSON.stringify(new URL("../cli.mjs", import.meta.url).href)}); console.log("alive");`,
  ], { cwd, encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, "alive\n");
  assert.deepEqual(await fs.readdir(cwd), []);
});

test("library requests enforce the same option validation as the CLI", () => {
  assert.throws(() => queryIndex({ files: [] }, { command: "find", query: "a", limit: 0 }), /limit/);
});
