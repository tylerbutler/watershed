import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import test from "node:test";

const repository = resolve(import.meta.dirname, "../..");

function recipeCommands(name) {
  const result = spawnSync("just", [
    "--color", "never", "--dry-run", name,
  ], { cwd: repository, encoding: "utf8" });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stderr);
  return `${result.stdout}${result.stderr}`.trim().split(/\r?\n/);
}

test("native gate selects both complete file suites and HTTP smokes", () => {
  assert.deepEqual(recipeCommands("shared-tree-test"), [
    "gleam test --target erlang -- shared_tree git_storage facade_parity",
    "gleam test --target javascript -- shared_tree git_storage facade_parity",
    "node smoke/shared_tree_storage.mjs",
    "node smoke/shared_tree_bootstrap.mjs",
    "node smoke/shared_tree_creation.mjs",
  ]);
});

test("acceptance delegates to the existing 200-schedule coordinator", () => {
  assert.deepEqual(recipeCommands("shared-tree-interop"), [
    "node smoke/shared_tree.mjs --profile test/fixtures/shared_tree/profile.json --iterations 200 --seed 42",
  ]);
});

test("deep acceptance uses the same coordinator with 5000 schedules", () => {
  assert.deepEqual(recipeCommands("shared-tree-interop-deep"), [
    "node smoke/shared_tree.mjs --profile test/fixtures/shared_tree/profile.json --iterations 5000 --seed 42",
  ]);
});

test("creation acceptance retains native checks and pinned-service proof", () => {
  assert.deepEqual(recipeCommands("shared-tree-create-interop"), [
    "gleam test --target erlang -- shared_tree_creation git_storage facade_parity",
    "gleam test --target javascript -- shared_tree_creation git_storage facade_parity",
    "node smoke/shared_tree_creation.mjs",
    "node tools/shared-tree-oracle/creation.mjs interop --local-floodgate",
  ]);
});
