import assert from "node:assert/strict";
import { existsSync, readdirSync } from "node:fs";
import { relative, resolve } from "node:path";
import test from "node:test";

const websiteRoot = resolve(import.meta.dirname, "..");
const manifestUrl = new URL("./test-files.mjs", import.meta.url);

function normalizeDiscoveredPath(file) {
  return file.replaceAll("\\", "/");
}

function discoverTests(directory) {
  return readdirSync(resolve(websiteRoot, directory), {
    recursive: true,
    withFileTypes: true,
  })
    .filter(
      (entry) =>
        entry.isFile() &&
        (entry.name.endsWith(".test.ts") || entry.name.endsWith(".test.mjs")),
    )
    .map((entry) =>
      normalizeDiscoveredPath(
        relative(websiteRoot, resolve(entry.parentPath, entry.name)),
      ),
    );
}

test("normalizes Windows-style discovered paths to manifest form", () => {
  assert.equal(
    normalizeDiscoveredPath(String.raw`scripts\test-files.test.mjs`),
    "scripts/test-files.test.mjs",
  );
});

test("classifies every test file in exactly one suite", async () => {
  assert.ok(existsSync(manifestUrl), "shared test manifest is missing");

  const { browserTestFiles, nodeTestFiles } = await import(manifestUrl.href);
  const discovered = [...discoverTests("src"), ...discoverTests("scripts")];
  const classified = [...nodeTestFiles, ...browserTestFiles];
  const duplicates = classified.filter(
    (file, index) => classified.indexOf(file) !== index,
  );
  const unclassified = discovered.filter((file) => !classified.includes(file));
  const missing = classified.filter((file) => !discovered.includes(file));

  assert.deepEqual(
    { duplicates, missing, unclassified },
    { duplicates: [], missing: [], unclassified: [] },
  );
});
