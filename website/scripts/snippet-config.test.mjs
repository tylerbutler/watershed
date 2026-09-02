// ──────────────────────────────────────────────────────────────────────────
// Snippet configuration integration test — dependency-free checks that
// the repository's snippet configuration is complete and that generation
// works end-to-end.
//
// These tests exercise the seams the Gleam package tests must not know
// about: watershed-specific area counts, the sourceRoot that ties the
// configuration to the repository, and the markerRoots that tell the
// scanner where markers can live.
//
// The generate-and-validate suite deletes the output, regenerates it
// through the real CLI, and verifies the JSON. The atomic-preservation
// suite mutates a marker in a fixture, proves generation fails, and
// verifies the prior output survived.
//
// Run: node scripts/snippet-config.test.mjs
// ──────────────────────────────────────────────────────────────────────────
import { describe, it, before, after } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync, unlinkSync, writeFileSync, copyFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const websiteRoot = resolve(__dirname, "..");
const repoRoot = resolve(websiteRoot, "..");
const configPath = resolve(websiteRoot, "snippets.json");
const manifestPath = resolve(websiteRoot, "src/generated/snippets.json");
const generatorDir = resolve(repoRoot, "tools/source-snippets");

const config = JSON.parse(readFileSync(configPath, "utf-8"));

// ══════════════════════════════════════════════════════════════════════════
// Configuration shape — sourceRoot and markerRoots resolve to real paths
// ══════════════════════════════════════════════════════════════════════════

describe("configuration resolves to the repository", () => {
  const resolvedRoot = resolve(websiteRoot, config.sourceRoot);

  it("sourceRoot resolves to the repository root", () => {
    assert.ok(
      existsSync(resolve(resolvedRoot, "gleam.toml")),
      `sourceRoot "${config.sourceRoot}" does not resolve to a directory with gleam.toml`,
    );
    assert.ok(
      existsSync(resolve(resolvedRoot, "examples")),
      `sourceRoot "${config.sourceRoot}" does not resolve to a directory with examples/`,
    );
  });

  it("every markerRoot exists", () => {
    for (const root of config.markerRoots) {
      const absRoot = resolve(resolvedRoot, root);
      assert.ok(
        existsSync(absRoot),
        `markerRoot "${root}" does not exist at ${absRoot}`,
      );
    }
  });

  it("extensions include .gleam and .mjs", () => {
    assert.ok(config.extensions.includes(".gleam"), "extensions must include .gleam");
    assert.ok(config.extensions.includes(".mjs"), "extensions must include .mjs");
  });
});

// ══════════════════════════════════════════════════════════════════════════
// Inventory by area — the 78-id two-way check, broken down
// ══════════════════════════════════════════════════════════════════════════

describe("inventory counts by area", () => {
  const ids = config.snippets.map((s) => s.id);

  const count = (prefix) => ids.filter((id) => id.startsWith(prefix)).length;

  it("guide and foundations sheets: 51 snippets", () => {
    assert.equal(count("guide-") + count("foundations-"), 51);
  });

  it("field note practices: 17 snippets", () => {
    assert.equal(count("practice-"), 17);
  });

  it("homepage, runtime, and p2p: 3 snippets", () => {
    assert.equal(count("homepage-") + count("optimistic-") + count("p2p-"), 3);
  });

  it("SharedTree comparison: 7 snippets", () => {
    assert.equal(count("sharedtree-"), 7);
  });

  it("total: 78 snippets", () => {
    assert.equal(ids.length, 78);
  });
});

// ══════════════════════════════════════════════════════════════════════════
// Generate from scratch — delete output, regenerate, validate
// ══════════════════════════════════════════════════════════════════════════

describe("generate from scratch", () => {
  /** Stash a copy so other tests are not affected. */
  let stashedManifest;

  before(() => {
    if (existsSync(manifestPath)) {
      stashedManifest = readFileSync(manifestPath);
    }
  });

  after(() => {
    if (stashedManifest !== undefined) {
      writeFileSync(manifestPath, stashedManifest);
    }
  });

  it("regenerates a valid manifest from an empty state", () => {
    // Delete the output.
    if (existsSync(manifestPath)) unlinkSync(manifestPath);
    assert.ok(!existsSync(manifestPath), "manifest should be gone");

    // Regenerate.
    execFileSync("gleam", [
      "run", "-m", "source_snippets/cli", "--",
      configPath, manifestPath,
    ], { cwd: generatorDir, timeout: 60_000 });

    assert.ok(existsSync(manifestPath), "manifest should be regenerated");

    const manifest = JSON.parse(readFileSync(manifestPath, "utf-8"));
    assert.equal(manifest.version, 1, "manifest version");
    const generatedIds = Object.keys(manifest.snippets).sort();
    const configuredIds = config.snippets.map((s) => s.id).sort();
    assert.deepEqual(generatedIds, configuredIds, "generated ids must match configured ids");

    // Every entry has non-empty code.
    for (const [id, entry] of Object.entries(manifest.snippets)) {
      assert.ok(entry.code.trim().length > 0, `${id} generated empty code`);
      assert.ok(!entry.code.includes("docs:snippet-"), `${id} leaks a marker directive`);
    }
  });
});

// ══════════════════════════════════════════════════════════════════════════
// Atomic preservation — mutate a fixture, prove failure preserves output
// ══════════════════════════════════════════════════════════════════════════

describe("atomic preservation on generation failure", () => {
  // Pick a source file the config references and temporarily break a marker.
  const firstMarkerSnippet = config.snippets.find((s) => s.markers && s.markers.length > 0);
  const fixtureRelPath = firstMarkerSnippet?.sourcePath;
  const fixtureAbsPath = fixtureRelPath
    ? resolve(websiteRoot, config.sourceRoot, fixtureRelPath)
    : null;

  let originalContent;
  let manifestBefore;

  before(() => {
    // Ensure a good manifest exists first.
    execFileSync("gleam", [
      "run", "-m", "source_snippets/cli", "--",
      configPath, manifestPath,
    ], { cwd: generatorDir, timeout: 60_000 });

    manifestBefore = readFileSync(manifestPath, "utf-8");

    if (fixtureAbsPath && existsSync(fixtureAbsPath)) {
      originalContent = readFileSync(fixtureAbsPath, "utf-8");
      // Remove the end marker for the first marker — this creates an
      // unmatched start, which the generator must reject.
      const markerId = firstMarkerSnippet.markers[0];
      const broken = originalContent.replace(
        new RegExp(`^\\s*//\\s*docs:snippet-end\\s+${markerId}\\s*$`, "m"),
        "// DELIBERATELY BROKEN — integration test",
      );
      assert.notEqual(broken, originalContent, "should have mutated the marker");
      writeFileSync(fixtureAbsPath, broken);
    }
  });

  after(() => {
    // Restore the original fixture.
    if (fixtureAbsPath && originalContent !== undefined) {
      writeFileSync(fixtureAbsPath, originalContent);
    }
  });

  it("generation fails on a broken marker", () => {
    if (!fixtureAbsPath) {
      assert.fail("no marker-based snippet in config to test with");
    }

    let threw = false;
    try {
      execFileSync("gleam", [
        "run", "-m", "source_snippets/cli", "--",
        configPath, manifestPath,
      ], { cwd: generatorDir, timeout: 60_000, stdio: "pipe" });
    } catch {
      threw = true;
    }
    assert.ok(threw, "generation should fail when a marker is broken");
  });

  it("the prior manifest is preserved after a failed generation", () => {
    if (!fixtureAbsPath) {
      assert.fail("no marker-based snippet in config to test with");
    }

    assert.ok(existsSync(manifestPath), "manifest should still exist");
    const manifestAfter = readFileSync(manifestPath, "utf-8");
    assert.equal(manifestAfter, manifestBefore, "manifest content should be unchanged after failed generation");
  });
});
