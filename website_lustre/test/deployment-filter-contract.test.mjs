import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, relative, resolve, sep } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const site = resolve(repoRoot, "website_lustre/dist");
const workflow = await readFile(
  resolve(repoRoot, ".github/workflows/website-lustre.yml"),
  "utf8",
);
const entries = [
  "counter_bug",
  "directory",
  "guide_race",
  "home",
  "json_ot",
  "mv_register",
  "rich_text",
  "sequence",
  "structure_sheet",
  "sudoku",
  "text",
];

function survivesDeploymentFilters(path) {
  return !relative(site, path).split(sep).some((part) => part.startsWith("."));
}

async function moduleDependencies(entry) {
  const pending = [entry];
  const dependencies = new Set();
  while (pending.length > 0) {
    const path = pending.pop();
    if (dependencies.has(path)) continue;
    dependencies.add(path);
    const source = await readFile(path, "utf8");
    for (const match of source.matchAll(
      /\b(?:import|export)\s*(?:[^"'()]*?\sfrom\s*)?["']([^"']+)["']/g,
    )) {
      if (match[1].startsWith(".")) {
        pending.push(resolve(dirname(path), match[1]));
      }
    }
  }
  return dependencies;
}

test("deployment filters retain every stable entry dependency", async () => {
  assert.match(
    workflow,
    /actions\/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02/,
  );
  assert.doesNotMatch(workflow, /include-hidden-files:\s*true/);
  assert.match(workflow, /netlify-cli@27\.4\.1/);

  for (const entry of entries) {
    for (const dependency of await moduleDependencies(
      resolve(site, `${entry}.js`),
    )) {
      assert.equal(
        survivesDeploymentFilters(dependency),
        true,
        `${entry}.js depends on filtered path ${relative(site, dependency)}`,
      );
    }
  }
});
