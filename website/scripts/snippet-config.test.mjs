// ──────────────────────────────────────────────────────────────────────────
// Snippet configuration integration test — dependency-free checks that
// the repository's snippet configuration is complete and that generation
// works end-to-end.
//
// These tests exercise the seams the Gleam package tests must not know
// about: watershed-specific area counts, the sourceRoot that ties the
// configuration to this repository, the generated directories the scan must
// skip, and the proof that every tracked source of every configured
// extension is inside a marker root or a named exclusion.
//
// The generate-and-validate suite deletes the output, regenerates it
// through the real CLI, and verifies the JSON. The atomic-preservation
// suite copies one source and a derived configuration into an ignored
// sandbox, breaks a marker in the copy, and proves the prior output
// survives the failed run. No tracked file is ever written.
//
// Run: node scripts/snippet-config.test.mjs
// ──────────────────────────────────────────────────────────────────────────
import { describe, it, before, after } from "node:test";
import assert from "node:assert/strict";
import {
  readFileSync,
  existsSync,
  unlinkSync,
  writeFileSync,
  mkdirSync,
  rmSync,
  globSync,
} from "node:fs";
import { resolve, dirname, relative } from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const websiteRoot = resolve(__dirname, "..");
const repoRoot = resolve(websiteRoot, "..");
const configPath = resolve(websiteRoot, "snippets.json");
const manifestPath = resolve(websiteRoot, "src/generated/snippets.json");
const generatorDir = resolve(repoRoot, "tools/source-snippets");
const sandboxRoot = resolve(websiteRoot, ".tmp/snippet-config");

const config = JSON.parse(readFileSync(configPath, "utf-8"));

/** Runs the generator CLI. Returns the exit status and captured stderr. */
function runGenerator(cfg, out) {
  try {
    execFileSync(
      "gleam",
      ["run", "-m", "source_snippets/cli", "--", cfg, out],
      { cwd: generatorDir, timeout: 120_000, stdio: "pipe" },
    );
    return { ok: true, stderr: "" };
  } catch (error) {
    return { ok: false, stderr: String(error.stderr ?? "") };
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Configuration shape — sourceRoot ties the configuration to this checkout
//
// The Gleam generator already rejects a marker root that does not exist, so
// this suite does not repeat that. It pins the one fact the generator cannot
// know: `sourceRoot` names *this* repository, which is what makes the
// coverage proof below meaningful.
// ══════════════════════════════════════════════════════════════════════════

describe("configuration resolves to the repository", () => {
  const resolvedRoot = resolve(websiteRoot, config.sourceRoot);

  it("sourceRoot resolves to the repository root", () => {
    assert.equal(
      resolvedRoot,
      repoRoot,
      `sourceRoot "${config.sourceRoot}" does not resolve to the repository root`,
    );
    assert.ok(
      existsSync(resolve(resolvedRoot, "gleam.toml")),
      `sourceRoot "${config.sourceRoot}" does not resolve to a directory with gleam.toml`,
    );
  });

  it("extensions include .gleam and .mjs", () => {
    assert.ok(config.extensions.includes(".gleam"), "extensions must include .gleam");
    assert.ok(
      config.extensions.includes(".mjs"),
      "extensions must include .mjs — FFI modules carry markers too",
    );
  });
});

// ══════════════════════════════════════════════════════════════════════════
// Scanner exclusions — the generated directories the scan must not descend
//
// A broad marker root reaches generated output: the Gleam compiler writes a
// copy of every marked source under `build/`, and esbuild writes a bundle of
// the same code under `dist/`. A copy carries the same marker ids as its
// original, so a scan that reads it reports a duplicate — or worse, quotes
// the copy. Naming the generated directories keeps the scan on the sources
// a person edits.
// ══════════════════════════════════════════════════════════════════════════

/** Every directory name the scan must skip, with the reason it is there and
 *  a probe that proves the directory is real. A probe that finds nothing
 *  means the exclusion has outlived the directory it was written for. */
const SCANNER_EXCLUSIONS = [
  {
    name: "build",
    reason: "the Gleam compiler's copy of every source it compiles",
    probe: "examples/*/build",
  },
  {
    name: "dist",
    reason: "the esbuild bundle of the example applications",
    probe: "examples/*/dist",
  },
  {
    name: "node_modules",
    reason: "vendored packages nobody in this repository edits",
    probe: "website/node_modules",
  },
  {
    name: ".git",
    reason: "object storage, not source",
    probe: ".git",
  },
];

describe("the scan skips every generated directory", () => {
  for (const exclusion of SCANNER_EXCLUSIONS) {
    it(`excludeDirs names "${exclusion.name}"`, () => {
      assert.ok(
        config.excludeDirs.includes(exclusion.name),
        `excludeDirs must name "${exclusion.name}" — ${exclusion.reason}`,
      );
    });
  }

  it("every named exclusion still matches a real path", () => {
    // A worktree keeps `.git` as a file, not a directory, so the probe asks
    // only that the path exists. The scan compares directory names, and a
    // name that matches nothing here has outlived its reason.
    for (const exclusion of SCANNER_EXCLUSIONS) {
      const matches = globSync(exclusion.probe, { cwd: repoRoot });
      assert.ok(
        matches.length > 0,
        `exclusion "${exclusion.name}" (${exclusion.reason}) matches nothing under "${exclusion.probe}" — drop it`,
      );
    }
  });

  it("the excluded directories hold files the scan would otherwise read", () => {
    // Without this, `dist` and `build` would be decoration. A bundle with a
    // scanned extension inside an excluded directory under a marker root is
    // exactly the file the exclusion exists to hide.
    const scannable = globSync(
      config.extensions.map((ext) => `examples/*/dist/**/*${ext}`),
      { cwd: repoRoot },
    );
    assert.ok(
      scannable.length > 0,
      "no bundled output under examples/*/dist — regenerate the examples, or drop the dist exclusion",
    );
    for (const bundled of scannable) {
      assert.equal(
        coverageOf(bundled).kind,
        "uncovered",
        `${bundled} is generated output but the coverage model treats it as scanned`,
      );
    }
  });
});

// ══════════════════════════════════════════════════════════════════════════
// Coverage — every tracked source is scanned or named as an exception
//
// A marker in an unscanned file is invisible: it is never checked for a
// missing pair and never reported as unreferenced. Broad roots plus scanner
// exclusions keep that surface at zero, and this suite is the proof. The
// check runs for every configured extension, because a marker in an FFI
// module is as invisible as a marker in a Gleam module. A new package that
// lands outside every root fails here until it is added or excluded on
// purpose.
// ══════════════════════════════════════════════════════════════════════════

/** Directories whose sources are deliberately outside every marker root.
 *  Each entry needs a reason, and each must still match a tracked file, so
 *  a stale exception cannot sit here unnoticed. */
const COVERAGE_EXCLUSIONS = [
  {
    prefix: "tools/compile-fail/",
    reason:
      "fixtures that must fail to compile — nothing on the site quotes them",
  },
  {
    prefix: "tools/source-snippets/",
    reason:
      "the generator and its own throwaway fixtures, whose marker names would collide with the repository's",
  },
  {
    prefix: "tools/nostr/",
    reason: "a relay probe run by hand, never quoted on the site",
  },
  {
    prefix: "tools/relay/",
    reason: "the local development relay, not library code the site teaches",
  },
  {
    prefix: "tools/signaling/",
    reason:
      "the local development signaling server, not library code the site teaches",
  },
  {
    prefix: "smoke/",
    reason:
      "the browser smoke harness — it drives the examples, it is not an example",
  },
  {
    prefix: "website/",
    reason:
      "the site itself renders snippets; the sources it quotes live in tools/website-samples",
  },
  {
    prefix: ".agents/",
    reason: "skill assets vendored by apm install, overwritten on every sync",
  },
];

/** Tracked files with the given extension, repo-relative. */
function trackedFiles(extension) {
  const output = execFileSync("git", ["ls-files", `*${extension}`], {
    cwd: repoRoot,
    encoding: "utf-8",
    maxBuffer: 32 * 1024 * 1024,
  });
  return output.split("\n").filter((line) => line.length > 0);
}

/** Every tracked file the generator would read, across all extensions. */
function allTrackedSources() {
  return config.extensions.flatMap(trackedFiles);
}

/**
 * Classifies one repo-relative path against the scan the generator performs.
 *
 * The scan never descends into an excluded directory, so a file inside one
 * is not covered by the marker root above it. That check comes first: a
 * bundle under `examples/foo/dist/` sits below the `examples` root, and
 * reading the root alone would call it scanned when it is not.
 */
function coverageOf(
  relPath,
  { roots = config.markerRoots, excludeDirs = config.excludeDirs } = {},
) {
  const exclusion = COVERAGE_EXCLUSIONS.find((e) => relPath.startsWith(e.prefix));
  const blocked = relPath
    .split("/")
    .slice(0, -1)
    .find((segment) => excludeDirs.includes(segment));
  if (blocked) {
    return exclusion
      ? { kind: "exclusion", prefix: exclusion.prefix }
      : { kind: "uncovered", blocked };
  }
  const root = roots.find((r) => relPath === r || relPath.startsWith(`${r}/`));
  if (root) return { kind: "root", root };
  if (exclusion) return { kind: "exclusion", prefix: exclusion.prefix };
  return { kind: "uncovered" };
}

for (const extension of config.extensions) {
  describe(`every tracked ${extension} source is scanned or excluded on purpose`, () => {
    const tracked = trackedFiles(extension);

    it(`git reports the tracked ${extension} sources`, () => {
      assert.ok(
        tracked.length > 10,
        `only ${tracked.length} tracked ${extension} files — the scan is not finding the repository`,
      );
    });

    it(`no tracked ${extension} source falls outside every root and exclusion`, () => {
      const uncovered = tracked
        .filter((p) => coverageOf(p).kind === "uncovered")
        .sort();
      assert.deepEqual(
        uncovered,
        [],
        `these tracked ${extension} sources are never scanned for markers — add a markerRoot or a documented exclusion:\n${uncovered.join("\n")}`,
      );
    });
  });
}

describe("every tracked source is scanned or excluded on purpose", () => {
  const tracked = allTrackedSources();

  it("every exclusion still matches a tracked source", () => {
    for (const exclusion of COVERAGE_EXCLUSIONS) {
      const matches = tracked.filter((p) => p.startsWith(exclusion.prefix));
      assert.ok(
        matches.length > 0,
        `exclusion "${exclusion.prefix}" (${exclusion.reason}) matches nothing — drop it`,
      );
    }
  });

  it("every marker root still holds a tracked source", () => {
    for (const root of config.markerRoots) {
      const matches = tracked.filter(
        (p) => p === root || p.startsWith(`${root}/`),
      );
      assert.ok(
        matches.length > 0,
        `markerRoot "${root}" holds no tracked source — drop it`,
      );
    }
  });

  it("FFI modules beside the marked Gleam sources are scanned", () => {
    const ffi = trackedFiles(".mjs").filter((p) => p.endsWith("_ffi.mjs"));
    assert.ok(ffi.length > 0, "no tracked FFI modules");
    const outside = ffi.filter((p) => coverageOf(p).kind !== "root").sort();
    assert.deepEqual(
      outside,
      [],
      `these FFI modules sit beside marked Gleam sources but are not scanned:\n${outside.join("\n")}`,
    );
  });

  it("example dev harnesses are scanned", () => {
    const devSources = tracked.filter((p) => /^examples\/[^/]+\/dev\//.test(p));
    assert.ok(devSources.length > 0, "no examples/*/dev sources are tracked");
    for (const devSource of devSources) {
      assert.equal(
        coverageOf(devSource).kind,
        "root",
        `${devSource} is not under a marker root`,
      );
    }
  });

  describe("mutation — the coverage check is load-bearing", () => {
    it("a package outside every root and exclusion is uncovered", () => {
      assert.equal(coverageOf("tools/newly_added/src/thing.gleam").kind, "uncovered");
    });

    it("a module outside every root and exclusion is uncovered", () => {
      assert.equal(coverageOf("tools/newly_added/index.mjs").kind, "uncovered");
    });

    it("dropping a root uncovers the sources it held", () => {
      const withoutExamples = config.markerRoots.filter((r) => r !== "examples");
      const anExample = tracked.find((p) => p.startsWith("examples/"));
      assert.ok(anExample, "expected at least one tracked example source");
      assert.equal(coverageOf(anExample).kind, "root");
      assert.equal(
        coverageOf(anExample, { roots: withoutExamples }).kind,
        "uncovered",
      );
    });

    it("an excluded path is reported as an exclusion, not as a root", () => {
      const excluded = tracked.find((p) =>
        p.startsWith("tools/source-snippets/"),
      );
      assert.ok(excluded, "expected a tracked generator source");
      assert.equal(coverageOf(excluded).kind, "exclusion");
    });

    it("a source inside an excluded directory is not covered by the root above it", () => {
      for (const excluded of config.excludeDirs) {
        const inside = `examples/an_example/${excluded}/thing.gleam`;
        assert.equal(
          coverageOf(inside).kind,
          "uncovered",
          `"${inside}" is inside excluded directory "${excluded}" — the scan never reads it`,
        );
      }
    });

    it("dropping an exclusion from excludeDirs calls the generated copy covered", () => {
      // Proves the excludeDirs term is what makes the check above fire, not
      // the marker roots.
      const bundled = "examples/an_example/dist/an_example.mjs";
      assert.equal(coverageOf(bundled).kind, "uncovered");
      assert.equal(
        coverageOf(bundled, {
          excludeDirs: config.excludeDirs.filter((d) => d !== "dist"),
        }).kind,
        "root",
      );
    });
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
    if (existsSync(manifestPath)) unlinkSync(manifestPath);
    assert.ok(!existsSync(manifestPath), "manifest should be gone");

    const run = runGenerator(configPath, manifestPath);
    assert.ok(run.ok, `generation failed:\n${run.stderr}`);
    assert.ok(existsSync(manifestPath), "manifest should be regenerated");

    const manifest = JSON.parse(readFileSync(manifestPath, "utf-8"));
    assert.equal(manifest.version, 1, "manifest version");
    const generatedIds = Object.keys(manifest.snippets).sort();
    const configuredIds = config.snippets.map((s) => s.id).sort();
    assert.deepEqual(generatedIds, configuredIds, "generated ids must match configured ids");

    for (const [id, entry] of Object.entries(manifest.snippets)) {
      assert.ok(entry.code.trim().length > 0, `${id} generated empty code`);
      assert.ok(!entry.code.includes("docs:snippet-"), `${id} leaks a marker directive`);
      assert.ok(
        !entry.sourcePath.split("/").some((s) => config.excludeDirs.includes(s)),
        `${id} cites "${entry.sourcePath}", which is inside an excluded directory`,
      );
    }
  });
});

// ══════════════════════════════════════════════════════════════════════════
// Atomic preservation — break a copied source, prove the output survives
//
// The mutation happens in an ignored sandbox holding a copy of one source
// and a configuration derived from the real one. Nothing git tracks is
// written, so a crash mid-test cannot damage the checkout.
// ══════════════════════════════════════════════════════════════════════════

describe("atomic preservation on generation failure", () => {
  const marked = config.snippets.find((s) => s.markers && s.markers.length > 0);
  const sandboxSourceRoot = resolve(sandboxRoot, "repo");
  const sandboxConfig = resolve(sandboxRoot, "snippets.json");
  const sandboxOutput = resolve(sandboxRoot, "out.json");

  /** The copied source, and the marker the test breaks in it. */
  const sourceRelPath = marked?.sourcePath;
  const brokenMarker = marked?.markers[0];
  const sandboxSource = sourceRelPath
    ? resolve(sandboxSourceRoot, sourceRelPath)
    : null;

  let goodOutput;

  before(() => {
    assert.ok(marked, "the configuration declares no marker-based snippet");

    rmSync(sandboxRoot, { recursive: true, force: true });
    mkdirSync(dirname(sandboxSource), { recursive: true });

    // The sandbox must be ignored: the test writes into it.
    const status = execFileSync(
      "git",
      ["check-ignore", relative(repoRoot, sandboxRoot)],
      { cwd: repoRoot, encoding: "utf-8" },
    );
    assert.ok(status.trim().length > 0, "the sandbox directory must be ignored");

    // Copy the one source, and derive a configuration that names every
    // snippet reading it. Any marker left unreferenced would fail the run
    // for the wrong reason.
    writeFileSync(
      sandboxSource,
      readFileSync(resolve(repoRoot, sourceRelPath), "utf-8"),
    );
    writeFileSync(
      sandboxConfig,
      JSON.stringify(
        {
          version: 1,
          sourceRoot: "repo",
          markerRoots: [dirname(sourceRelPath)],
          extensions: config.extensions,
          excludeDirs: config.excludeDirs,
          snippets: config.snippets.filter((s) => s.sourcePath === sourceRelPath),
        },
        null,
        2,
      ),
    );
  });

  after(() => {
    rmSync(sandboxRoot, { recursive: true, force: true });
  });

  it("the sandbox generates a good manifest first", () => {
    const run = runGenerator(sandboxConfig, sandboxOutput);
    assert.ok(run.ok, `sandbox generation failed:\n${run.stderr}`);
    goodOutput = readFileSync(sandboxOutput, "utf-8");

    const manifest = JSON.parse(goodOutput);
    assert.ok(
      Object.keys(manifest.snippets).includes(marked.id),
      `the sandbox manifest is missing "${marked.id}"`,
    );
  });

  it("removing an end marker fails the run with an extraction error", () => {
    const original = readFileSync(sandboxSource, "utf-8");
    const broken = original.replace(
      new RegExp(`^\\s*//\\s*docs:snippet-end\\s+${brokenMarker}\\s*$`, "m"),
      "// DELIBERATELY BROKEN — integration test",
    );
    assert.notEqual(broken, original, "the end marker should have been removed");
    writeFileSync(sandboxSource, broken);

    const run = runGenerator(sandboxConfig, sandboxOutput);
    assert.equal(run.ok, false, "generation should fail on an unpaired marker");
    assert.match(
      run.stderr,
      new RegExp(`snippet "${marked.id}": extraction failed`),
      `expected an extraction error for "${marked.id}", got:\n${run.stderr}`,
    );
  });

  it("the prior manifest survives the failed run", () => {
    assert.ok(existsSync(sandboxOutput), "the manifest should still exist");
    assert.equal(
      readFileSync(sandboxOutput, "utf-8"),
      goodOutput,
      "the manifest changed after a failed generation",
    );
    assert.ok(
      !existsSync(`${sandboxOutput}.tmp`),
      "the failed run left its scratch file behind",
    );
  });
});
