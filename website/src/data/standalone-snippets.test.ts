// ──────────────────────────────────────────────────────────────────────────
// Tests for Task 5 standalone snippet migration.
//
// Covers:
// 1. Gleam snippets extract cleanly from compiled sources
// 2. SharedTree TypeScript literals are valid syntax
// 3. No unapproved literal Gleam remains in migrated surfaces
// 4. Fixture is included in root build configuration
// ──────────────────────────────────────────────────────────────────────────
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  combineSnippets,
  originParts,
  snippetFromMarker,
  type Snippet,
} from "../lib/snippet.ts";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "../../..");

function readSource(repoRelative: string): string {
  return readFileSync(resolve(repoRoot, repoRelative), "utf-8");
}

// ── Source paths ───────────────────────────────────────────────────────────

const sourcePaths = {
  diceCLI: "examples/dice_cli/src/dice_cli.gleam",
  sudokuSchema: "examples/sudoku_lustre/src/sudoku_lustre/document_schema.gleam",
  sudokuComponent: "examples/sudoku_lustre/src/sudoku_lustre/component.gleam",
  boardSchema: "tools/website-samples/src/website_samples/board_schema.gleam",
  boardApp: "tools/website-samples/src/website_samples/board_app.gleam",
  optimistic: "tools/website-samples/src/website_samples/optimistic_sample.gleam",
  p2p: "tools/website-samples/src/website_samples/p2p_sample.gleam",
} as const;

// Build all snippets using readFileSync (same extraction as the registry).
function buildSnippets(): Record<string, Snippet> {
  const src = Object.fromEntries(
    Object.entries(sourcePaths).map(([k, v]) => [k, readSource(v)]),
  ) as Record<string, string>;

  return {
    "homepage-beam": snippetFromMarker(
      src.diceCLI, sourcePaths.diceCLI, "gleam", "homepage-beam",
    ),
    "optimistic-local": snippetFromMarker(
      src.optimistic, sourcePaths.optimistic, "gleam", "optimistic-local",
    ),
    "p2p-config": snippetFromMarker(
      src.p2p, sourcePaths.p2p, "gleam", "p2p-config",
    ),
    "sharedtree-declare": snippetFromMarker(
      src.boardSchema, sourcePaths.boardSchema, "gleam", "sharedtree-declare",
    ),
    "sharedtree-bootstrap": snippetFromMarker(
      src.boardApp, sourcePaths.boardApp, "gleam", "sharedtree-bootstrap",
    ),
    "sharedtree-read-write": snippetFromMarker(
      src.boardApp, sourcePaths.boardApp, "gleam", "sharedtree-read-write",
    ),
    "sharedtree-record": snippetFromMarker(
      src.boardApp, sourcePaths.boardApp, "gleam", "sharedtree-record",
    ),
    "sharedtree-events": snippetFromMarker(
      src.boardApp, sourcePaths.boardApp, "gleam", "sharedtree-events",
    ),
    "sharedtree-nest": [
      "sudoku-schema-head",
      "sudoku-schema-cells",
      "sudoku-schema-notes",
      "sudoku-schema-givens",
      "sudoku-schema-mistakes",
    ]
      .map((marker) =>
        snippetFromMarker(
          src.sudokuSchema, sourcePaths.sudokuSchema, "gleam", marker,
        ),
      )
      .reduce((joined, next) =>
        combineSnippets(joined, next, sourcePaths.sudokuSchema),
      ),
    "sharedtree-per-kind": snippetFromMarker(
      src.sudokuComponent, sourcePaths.sudokuComponent, "gleam", "sharedtree-per-kind",
    ),
  };
}

// ── 1. Registry extraction ─────────────────────────────────────────────────

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

  it("extracts all expected snippets without errors", () => {
    const snippets = buildSnippets();
    for (const key of EXPECTED_KEYS) {
      assert.ok(snippets[key], `missing snippet: ${key}`);
    }
  });

  it("every snippet has non-empty code", () => {
    const snippets = buildSnippets();
    for (const [key, snippet] of Object.entries(snippets)) {
      assert.ok(
        snippet.code.trim().length > 0,
        `empty code for snippet: ${key}`,
      );
    }
  });

  it("every snippet has a source-backed origin (marker)", () => {
    const snippets = buildSnippets();
    for (const [key, snippet] of Object.entries(snippets)) {
      for (const part of originParts(snippet.origin)) {
        assert.equal(
          part.kind,
          "marker",
          `snippet ${key} should use marker extraction`,
        );
      }
    }
  });

  it("homepage-beam contains watershed_beam.connect", () => {
    const snippets = buildSnippets();
    assert.match(snippets["homepage-beam"].code, /watershed_beam\.connect/);
  });

  it("homepage-beam contains watershed_beam.root", () => {
    const snippets = buildSnippets();
    assert.match(snippets["homepage-beam"].code, /watershed_beam\.root/);
  });

  it("optimistic-local contains watershed.set", () => {
    const snippets = buildSnippets();
    assert.match(snippets["optimistic-local"].code, /watershed\.set/);
  });

  it("p2p-config contains crdt_js.config", () => {
    const snippets = buildSnippets();
    assert.match(snippets["p2p-config"].code, /crdt_js\.config/);
  });

  it("sharedtree-declare contains pub type Board", () => {
    const snippets = buildSnippets();
    assert.match(snippets["sharedtree-declare"].code, /pub type Board/);
  });

  it("sharedtree-nest contains SudokuDocument", () => {
    const snippets = buildSnippets();
    assert.match(snippets["sharedtree-nest"].code, /SudokuDocument/);
  });
});

// ── 2. SharedTree TypeScript literals are syntactically valid ───────────────
// Read the actual registry source file and extract each ts-* snippet literal,
// so the syntax check stays in sync with the registry (no manual duplication).

/**
 * Extract template literal strings from the sharedtreeTypeScriptSnippets
 * record in standalone-snippets.ts. Returns a map of snippet id → code string.
 */
function extractTsSnippetsFromRegistry(): Record<string, string> {
  const registrySource = readFileSync(
    resolve(__dirname, "standalone-snippets.ts"),
    "utf-8",
  );

  // Find each "ts-*": snippetFromLiteral(`...`, block. Template literals in
  // the registry have no interpolation, so we scan for matching backticks.
  const result: Record<string, string> = {};
  const keyPattern = /"(ts-[^"]+)":\s*snippetFromLiteral\(\s*`/g;
  let match: RegExpExecArray | null;

  while ((match = keyPattern.exec(registrySource)) !== null) {
    const key = match[1];
    const codeStart = match.index + match[0].length;
    // Find the closing backtick that isn't escaped.
    let i = codeStart;
    while (i < registrySource.length) {
      if (registrySource[i] === "`" && registrySource[i - 1] !== "\\") break;
      i++;
    }
    result[key] = registrySource.slice(codeStart, i);
  }

  return result;
}

/** Strip import declarations from code — `new Function` cannot parse them. */
function stripImports(code: string): string {
  return code
    .split("\n")
    .filter((line) => !line.trimStart().startsWith("import "))
    .join("\n")
    .trim();
}

describe("sharedtree TypeScript syntax", () => {
  const tsSnippets = extractTsSnippetsFromRegistry();

  it("extracts at least 7 ts-* snippets from the registry", () => {
    const keys = Object.keys(tsSnippets);
    assert.ok(
      keys.length >= 7,
      `expected ≥7 ts-* snippets, found ${keys.length}: ${keys}`,
    );
  });

  for (const [key, code] of Object.entries(tsSnippets)) {
    it(`${key} (actual registry literal) is parseable JavaScript`, () => {
      const stripped = stripImports(code);
      assert.doesNotThrow(
        () => new Function(stripped),
        `TS snippet "${key}" has invalid syntax`,
      );
    });
  }
});

// ── 3. No unapproved literal Gleam in migrated surfaces ────────────────────

describe("no handwritten Gleam literals in migrated pages", () => {
  const migratedPages = [
    "src/components/CodeSample.astro",
    "src/pages/runtime/optimistic.astro",
    "src/pages/runtime/p2p.astro",
    "src/pages/sharedtree.astro",
  ];

  for (const page of migratedPages) {
    it(`${page} has no snippetFromLiteral gleam calls`, () => {
      const content = readFileSync(page, "utf8");
      const hasLiteralGleam =
        /snippetFromLiteral\s*\([\s\S]*?["']gleam["']/s.test(content);
      assert.ok(
        !hasLiteralGleam,
        `${page} still has a snippetFromLiteral("gleam") call`,
      );
    });

    it(`${page} has no inline Gleam template literal`, () => {
      const content = readFileSync(page, "utf8");
      const hasGleamLiteral =
        /`[^`]*import gleam\/[^`]*`/s.test(content);
      assert.ok(
        !hasGleamLiteral,
        `${page} still has an inline Gleam template literal`,
      );
    });
  }

  it("sharedtree.astro has no inline Gleam template literals", () => {
    const content = readFileSync("src/pages/sharedtree.astro", "utf8");
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
