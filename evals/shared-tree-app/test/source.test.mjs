import assert from "node:assert/strict";
import test from "node:test";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { snapshotWatershed } from "../lib/source.mjs";

const exec = promisify(execFile);
const repository = fileURLToPath(new URL("../../../", import.meta.url));

test("native validation snapshots the committed SDK without history or benchmark answers", async () => {
  const root = await mkdtemp(join(tmpdir(), "incident-source-test-"));
  try {
    const revision = (await exec("git", ["rev-parse", "HEAD"], { cwd: repository })).stdout.trim();
    const snapshot = await snapshotWatershed({ source: repository, revision, out: join(root, "sdk") });
    assert.equal(snapshot.revision, revision);
    const manifest = (await exec("git", ["show", `${revision}:gleam.toml`], { cwd: repository })).stdout;
    assert.equal(await readFile(join(snapshot.root, "gleam.toml"), "utf8"), manifest);
    const names = await readdir(snapshot.root, { recursive: true });
    assert.ok(names.includes("src/watershed/tree.gleam"));
    assert.ok(names.includes("watershed_lustre/src/watershed_lustre/tree.gleam"));
    assert.equal(names.some(name => /(^|\/)(\.git|examples|evals|test|validation|graders)(\/|$)/.test(name)), false);
    assert.equal(names.includes(".source.tar"), false);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("source selection rejects non-commit revisions before creating a snapshot", async () => {
  await assert.rejects(snapshotWatershed({
    source: repository, revision: "main", out: resolve(repository, "not-created-sdk"),
  }), /full commit SHA/);
});
