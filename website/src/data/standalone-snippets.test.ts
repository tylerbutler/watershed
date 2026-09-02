// ──────────────────────────────────────────────────────────────────────────
// Tests for the standalone snippet registry.
//
// Covers:
// 1. The generated Gleam snippets the homepage, runtime sheets, and the
//    SharedTree comparison quote
// 2. The Fluid TypeScript literals, parsed as written in the registry
// 3. No hand-written Gleam on the pages those snippets serve
// 4. The website fixture package is in the root build configuration
//
// Generate the manifest first: `just snippets`.
// Run: node --strip-types --test src/data/standalone-snippets.test.ts
// ──────────────────────────────────────────────────────────────────────────
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { isSourceBacked } from "../lib/snippet.ts";
import {
  sharedtreeTypeScriptSnippets,
  standaloneSnippets,
} from "./standalone-snippets.ts";

const __dirname = dirname(fileURLToPath(import.meta.url));
const websiteRoot = resolve(__dirname, "../..");
const repoRoot = resolve(__dirname, "../../..");

// ── 1. Generated Gleam snippets ────────────────────────────────────────────

describe("standalone snippet registry", () => {
  const EXPECTED_KEYS = [
    "homepage-beam",
    "optimistic-local",
    "p2p-config",
    "sharedtree-declare",
    "sharedtree-bootstrap",
    "sharedtree-read-write",
    "sharedtree-record",
    "sharedtree-events",
    "sharedtree-nest",
    "sharedtree-per-kind",
  ];

  it("serves every expected id, and nothing else", () => {
    assert.deepEqual(
      Object.keys(standaloneSnippets).sort(),
      [...EXPECTED_KEYS].sort(),
    );
  });

  it("every snippet has non-empty code", () => {
    for (const [key, snippet] of Object.entries(standaloneSnippets)) {
      assert.ok(
        snippet.code.trim().length > 0,
        `empty code for snippet: ${key}`,
      );
    }
  });

  it("every snippet is generated from marker ranges", () => {
    for (const [key, snippet] of Object.entries(standaloneSnippets)) {
      assert.ok(isSourceBacked(snippet), `${key} is not source-backed`);
      assert.equal(
        snippet.origin.kind,
        "source",
        `${key} should come from marker ranges`,
      );
    }
  });

  it("no snippet shows a marker directive to the reader", () => {
    for (const [key, snippet] of Object.entries(standaloneSnippets)) {
      assert.ok(
        !snippet.code.includes("docs:snippet-"),
        `${key} leaks a marker directive`,
      );
    }
  });

  it("every snippet cites a source file that exists", () => {
    for (const [key, snippet] of Object.entries(standaloneSnippets)) {
      assert.ok(
        readFileSync(resolve(repoRoot, snippet.sourcePath), "utf-8").length > 0,
        `${key} cites an empty file`,
      );
    }
  });

  it("homepage-beam contains watershed_beam.connect", () => {
    assert.match(standaloneSnippets["homepage-beam"].code, /watershed_beam\.connect/);
  });

  it("homepage-beam contains watershed_beam.root", () => {
    assert.match(standaloneSnippets["homepage-beam"].code, /watershed_beam\.root/);
  });

  it("optimistic-local contains watershed.set", () => {
    assert.match(standaloneSnippets["optimistic-local"].code, /watershed\.set/);
  });

  it("p2p-config contains crdt_js.config", () => {
    assert.match(standaloneSnippets["p2p-config"].code, /crdt_js\.config/);
  });

  it("sharedtree-declare contains pub type Board", () => {
    assert.match(standaloneSnippets["sharedtree-declare"].code, /pub type Board/);
  });

  it("sharedtree-nest contains SudokuDocument", () => {
    assert.match(standaloneSnippets["sharedtree-nest"].code, /SudokuDocument/);
  });
});

// ── 2. SharedTree TypeScript literals are syntactically valid ──────────────
// The literals are the code the page renders, so they are parsed as the
// registry exports them rather than scraped back out of its source text.

/** Strip import declarations from code — `new Function` cannot parse them. */
function stripImports(code: string): string {
  return code
    .split("\n")
    .filter((line) => !line.trimStart().startsWith("import "))
    .join("\n")
    .trim();
}

describe("sharedtree TypeScript syntax", () => {
  it("the registry exports at least 7 ts-* snippets", () => {
    const keys = Object.keys(sharedtreeTypeScriptSnippets);
    assert.ok(
      keys.length >= 7,
      `expected ≥7 ts-* snippets, found ${keys.length}: ${keys}`,
    );
    for (const key of keys) {
      assert.ok(key.startsWith("ts-"), `unexpected key in the TS registry: ${key}`);
    }
  });

  for (const [key, snippet] of Object.entries(sharedtreeTypeScriptSnippets)) {
    it(`${key} is a TypeScript literal, not source-backed`, () => {
      assert.equal(snippet.language, "typescript");
      assert.ok(
        !isSourceBacked(snippet),
        `${key} claims source provenance, but fluid-framework is external`,
      );
    });

    it(`${key} is parseable JavaScript`, () => {
      assert.doesNotThrow(
        () => new Function(stripImports(snippet.code)),
        `TS snippet "${key}" has invalid syntax`,
      );
    });
  }
});

// ── 3. No handwritten Gleam on the pages the registry serves ───────────────

describe("no handwritten Gleam literals in migrated pages", () => {
  const migratedPages = [
    "src/components/CodeSample.astro",
    "src/pages/runtime/optimistic.astro",
    "src/pages/runtime/p2p.astro",
    "src/pages/sharedtree.astro",
  ];

  for (const page of migratedPages) {
    const content = readFileSync(resolve(websiteRoot, page), "utf8");

    it(`${page} has no snippetFromLiteral gleam calls`, () => {
      assert.ok(
        !/snippetFromLiteral\s*\([\s\S]*?["']gleam["']/s.test(content),
        `${page} still has a snippetFromLiteral("gleam") call`,
      );
    });

    it(`${page} has no inline Gleam template literal`, () => {
      assert.ok(
        !/`[^`]*import gleam\/[^`]*`/s.test(content),
        `${page} still has an inline Gleam template literal`,
      );
    });
  }

  it("sharedtree.astro has no inline Gleam template literals", () => {
    const content = readFileSync(
      resolve(websiteRoot, "src/pages/sharedtree.astro"),
      "utf8",
    );
    const gleamConsts = content.match(/^const gleam\w+ = `/gm);
    assert.ok(
      !gleamConsts || gleamConsts.length === 0,
      `sharedtree.astro still has ${gleamConsts?.length} handwritten Gleam const(s): ${gleamConsts}`,
    );
  });
});

// ── 4. Fixture is in root build configuration ──────────────────────────────

describe("fixture build integration", () => {
  it("gleam.toml trellis @release excludes website-samples", () => {
    const toml = readFileSync(resolve(repoRoot, "gleam.toml"), "utf8");
    assert.match(toml, /tools\/website-samples/);
  });

  it("gleam.toml trellis test excludes website-samples (no test dir)", () => {
    const toml = readFileSync(resolve(repoRoot, "gleam.toml"), "utf8");
    const testSection = toml.match(/test\s*=\s*\[([^\]]+)\]/s);
    assert.ok(testSection, "test exclusion section not found");
    assert.match(testSection![1], /website-samples/);
  });

  it("gleam.toml trellis build-erlang excludes website-samples", () => {
    const toml = readFileSync(resolve(repoRoot, "gleam.toml"), "utf8");
    const section = toml.match(/build-erlang\s*=\s*\[([^\]]+)\]/s);
    assert.ok(section, "build-erlang exclusion section not found");
    assert.match(section![1], /website-samples/);
  });

  it("fixture gleam.toml targets javascript", () => {
    const toml = readFileSync(
      resolve(repoRoot, "tools/website-samples/gleam.toml"),
      "utf8",
    );
    assert.match(toml, /target\s*=\s*"javascript"/);
  });
});
