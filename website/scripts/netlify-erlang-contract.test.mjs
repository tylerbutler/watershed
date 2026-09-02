// ──────────────────────────────────────────────────────────────────────────
// Netlify Erlang toolchain contract — dependency-free check that the deploy
// configuration installs the Erlang packages the source-snippet prebuild
// needs.
//
// The website prebuild runs `tools/source-snippets`, an Erlang-target Gleam
// CLI, via `pnpm snippets`. Netlify's build image ships neither `escript`
// nor `erlc`, so the deploy must install them explicitly. This test verifies
// the three-file contract that makes that work:
//
//   1. website/Aptfile lists a package that provides escript and erlc
//   2. netlify.toml loads the apt plugin so the Aptfile is honoured
//   3. netlify-build.sh checks for escript/erlc before invoking gleam
//
// Run: node scripts/netlify-erlang-contract.test.mjs
// ──────────────────────────────────────────────────────────────────────────
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const websiteRoot = resolve(__dirname, "..");
const repoRoot = resolve(__dirname, "../..");

describe("Netlify Erlang toolchain contract", () => {
  // ── Aptfile ────────────────────────────────────────────────────────────

  it("website/Aptfile exists", () => {
    const aptfile = resolve(websiteRoot, "Aptfile");
    assert.ok(existsSync(aptfile), "website/Aptfile must exist so netlify-plugin-apt can install Erlang");
  });

  it("Aptfile lists an Erlang package that provides escript", () => {
    const aptfile = resolve(websiteRoot, "Aptfile");
    const content = readFileSync(aptfile, "utf8");
    const lines = content
      .split("\n")
      .map((l) => l.replace(/#.*/, "").trim())
      .filter(Boolean);

    // erlang-base provides /usr/bin/escript and /usr/bin/erlc on Ubuntu.
    // Any package whose name starts with erlang- and includes "base" counts;
    // the exact name may drift across Ubuntu releases.
    const hasErlang = lines.some((l) => /^erlang/.test(l));
    assert.ok(hasErlang, `Aptfile must list an erlang package; found lines: ${JSON.stringify(lines)}`);
  });

  // ── netlify.toml ──────────────────────────────────────────────────────

  it("netlify.toml configures the apt plugin", () => {
    const toml = readFileSync(resolve(repoRoot, "netlify.toml"), "utf8");
    assert.ok(
      /netlify-plugin-apt/.test(toml),
      "netlify.toml must reference netlify-plugin-apt so the Aptfile is honoured during deploy",
    );
  });

  // ── netlify-build.sh ──────────────────────────────────────────────────

  it("netlify-build.sh checks for escript before building", () => {
    const script = readFileSync(resolve(websiteRoot, "scripts", "netlify-build.sh"), "utf8");
    assert.ok(/escript/.test(script), "netlify-build.sh must verify escript is available");
  });

  it("netlify-build.sh checks for erlc before building", () => {
    const script = readFileSync(resolve(websiteRoot, "scripts", "netlify-build.sh"), "utf8");
    assert.ok(/erlc/.test(script), "netlify-build.sh must verify erlc is available");
  });
});
