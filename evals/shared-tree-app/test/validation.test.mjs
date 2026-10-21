import assert from "node:assert/strict";
import { cp, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { applyMutation, mutations, substitute } from "../validation/mutations.mjs";

const root = fileURLToPath(new URL("../", import.meta.url));

test("named mutation substitutions preserve surrounding source and reject missing or ambiguous hooks", () => {
  const source = "before\n// mutation:start edit\noriginal\n// mutation:end edit\nafter\n";
  assert.equal(substitute(source, "edit", "replacement"),
    "before\n// mutation:start edit\nreplacement\n// mutation:end edit\nafter\n");
  for (const invalid of ["no marker", source + source, source.replace("mutation:end", "not-an-end")]) {
    assert.throws(() => substitute(invalid, "edit", "replacement"), /exactly one.*edit/);
  }
});

test("all private behavioral mutants materialize for both SDKs without touching the starter", async () => {
  await mkdir(join(root, ".work"), { recursive: true });
  const work = await mkdtemp(join(root, ".work/mutation-unit-"));
  try {
    for (const sdk of ["watershed", "fluid"]) {
      for (const defect of Object.keys(mutations)) {
        const workspace = join(work, `${sdk}-${defect}`);
        const directory = join(workspace, sdk === "fluid" ? "src" : "src/incident_eval");
        await mkdir(directory, { recursive: true });
        for (const name of ["model", "schema"]) await cp(
          join(root, "validation/solutions", sdk, `${name}.${sdk === "fluid" ? "ts" : "gleam"}`),
          join(directory, `${name}.${sdk === "fluid" ? "ts" : "gleam"}`));
        await writeFile(join(workspace, "index.html"), "<main>protected shell</main>\n");
        const before = await Promise.all(["model", "schema"].map(name =>
          readFile(join(directory, `${name}.${sdk === "fluid" ? "ts" : "gleam"}`), "utf8")));
        await applyMutation({ sdk, defect, workspace });
        const after = await Promise.all(["model", "schema"].map(name =>
          readFile(join(directory, `${name}.${sdk === "fluid" ? "ts" : "gleam"}`), "utf8")));
        if (defect === "edit-shell") {
          assert.deepEqual(after, before);
          assert.notEqual(await readFile(join(workspace, "index.html"), "utf8"), "<main>protected shell</main>\n");
        } else {
          assert.notDeepEqual(after, before, `${sdk}/${defect} must change candidate behavior`);
          assert.equal(await readFile(join(workspace, "index.html"), "utf8"), "<main>protected shell</main>\n");
        }
      }
    }
    await assert.rejects(applyMutation({ sdk: "unknown", defect: "local-only", workspace: work }), /Unknown SDK/);
    await assert.rejects(applyMutation({ sdk: "fluid", defect: "unknown", workspace: work }), /Unknown mutation/);
  } finally { await rm(work, { recursive: true, force: true }); }
});
