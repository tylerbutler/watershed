import assert from "node:assert/strict";
import { cp, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { benchmarkProvenance } from "../generate.mjs";

test("portable provenance distinguishes controller changes from selected-starter changes", async () => {
  const root = await mkdtemp(join(tmpdir(), "shared-tree-provenance-"));
  const benchmark = fileURLToPath(new URL("../", import.meta.url));
  try {
    await cp(benchmark, root, { recursive: true, filter: path =>
      !relative(benchmark, path).split("/").some(part =>
        ["node_modules", ".work", "build", "dist", "test", "validation"].includes(part)) });
    const before = await benchmarkProvenance({ sdk: "watershed", root });
    await writeFile(join(root, "run.mjs"), "changed controller");
    const controllerChanged = await benchmarkProvenance({ sdk: "watershed", root });
    assert.notEqual(controllerChanged.evalSha256, before.evalSha256);
    assert.equal(controllerChanged.starterSha256, before.starterSha256);
    await writeFile(join(root, "watershed/src/incident_eval/model.gleam"), "changed starter");
    const starterChanged = await benchmarkProvenance({ sdk: "watershed", root });
    assert.equal(starterChanged.evalSha256, controllerChanged.evalSha256);
    assert.notEqual(starterChanged.starterSha256, controllerChanged.starterSha256);
  } finally { await rm(root, { recursive: true, force: true }); }
});
