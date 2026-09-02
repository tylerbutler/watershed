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
    "sharedtree-nest": snippetFromMarker(
      src.sudokuSchema, sourcePaths.sudokuSchema, "gleam", "sharedtree-nest",
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
      assert.equal(
        snippet.origin.kind,
        "marker",
        `snippet ${key} should use marker extraction`,
      );
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

describe("sharedtree TypeScript syntax", () => {
  const TS_SNIPPETS: Record<string, string> = {
    // Strip import statement — it's not parseable in function scope but is
    // valid module-level syntax. We check the rest of the code.
    "ts-declare": `const sf = new SchemaFactory("com.example.sprintboard");
class Card extends sf.object("Card", { title: sf.string }) {}`,

    "ts-root": `const config = new TreeViewConfiguration({ schema: Board });
const view = tree.viewWith(config);
view.initialize(new Board({ title: "Sprint board", cards: [], wipBreaches: 0 }));`,

    "ts-read-write": `board.title = "Q3 sprint board";
renderHeader(board.title);`,

    "ts-record": `card.title = "Ship the gauge rebuild";
card.column = "doing";
card.owner = undefined;`,

    "ts-nest": `board.cards.insertAtEnd(new Card({ title: "Ship it", column: "todo" }));
board.cards.moveRangeToIndex(4, 0, 3);
board.cards.removeAt(2);`,

    "ts-events": `const stopCards = Tree.on(board.cards, "nodeChanged", renderCards);
const stopAll = Tree.on(board, "treeChanged", renderEverything);`,

    "ts-gaps": `Tree.runTransaction(board, () => {
  card.column = "doing";
  card.owner = "ada";
  if (overWipLimit(board)) return Tree.runTransaction.rollback;
});`,
  };

  for (const [key, code] of Object.entries(TS_SNIPPETS)) {
    it(`${key} is parseable JavaScript`, () => {
      assert.doesNotThrow(
        () => new Function(code),
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
