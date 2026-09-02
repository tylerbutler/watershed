// ──────────────────────────────────────────────────────────────────────────
// Tests for the guide snippet registry.
//
// The registry is the seam the guide reads whole-file listings through.
// It renders the same code the Gleam manifest generates for the same id,
// so the swap in the next task changes where the string comes from and
// nothing else.
//
// The registry imports Gleam source with Vite's `?raw`, which Node cannot
// resolve, so the selection is replicated here with readFileSync — the same
// approach the practice and standalone suites take — and the registry module
// is read as text to prove the two agree.
//
// Run: node --strip-types --test src/data/guide-snippets.test.ts
// ──────────────────────────────────────────────────────────────────────────
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  isSourceBacked,
  snippetFromWholeFile,
  type Snippet,
} from "../lib/snippet.ts";

const __dirname = dirname(fileURLToPath(import.meta.url));
const websiteRoot = resolve(__dirname, "../..");
const repoRoot = resolve(__dirname, "../../..");

// ── Source paths ───────────────────────────────────────────────────────────

const sourcePaths = {
  retroSchema:
    "examples/retro_tutorial_lustre/src/retro_tutorial_lustre/document_schema.gleam",
} as const;

/** Every id the registry serves. */
const EXPECTED_IDS = ["guide-connect-schema"];

function readRepoFile(repoRelative: string): string {
  return readFileSync(resolve(repoRoot, repoRelative), "utf-8");
}

function readWebsiteFile(websiteRelative: string): string {
  return readFileSync(resolve(websiteRoot, websiteRelative), "utf-8");
}

// Replicate the registry's selection using readFileSync instead of ?raw.
function buildSnippets(): Record<string, Snippet> {
  return {
    "guide-connect-schema": snippetFromWholeFile(
      readRepoFile(sourcePaths.retroSchema), sourcePaths.retroSchema, "gleam",
    ),
  };
}

// ── 1. Registry selection ──────────────────────────────────────────────────

describe("guide snippet registry", () => {
  it("serves every expected id", () => {
    const snippets = buildSnippets();
    assert.deepEqual(Object.keys(snippets).sort(), [...EXPECTED_IDS].sort());
  });

  it("every snippet has non-empty code", () => {
    for (const [id, snippet] of Object.entries(buildSnippets())) {
      assert.ok(snippet.code.trim().length > 0, `empty code for snippet: ${id}`);
    }
  });

  it("every snippet is source-backed, never a literal", () => {
    for (const [id, snippet] of Object.entries(buildSnippets())) {
      assert.ok(isSourceBacked(snippet), `${id} is not source-backed`);
    }
  });

  it("no snippet shows a marker directive to the reader", () => {
    for (const [id, snippet] of Object.entries(buildSnippets())) {
      assert.ok(
        !snippet.code.includes("docs:snippet-"),
        `${id} leaks a marker directive`,
      );
    }
  });
});

// ── 2. The whole-file listing ──────────────────────────────────────────────

describe("guide-connect-schema is the whole schema module", () => {
  it("declares the schema module as its source", () => {
    const snippet = buildSnippets()["guide-connect-schema"];
    assert.equal(snippet.sourcePath, sourcePaths.retroSchema);
    assert.deepEqual(snippet.origin, { kind: "file" });
    assert.equal(snippet.language, "gleam");
  });

  it("keeps the module documentation header the guide sheet shows", () => {
    const snippet = buildSnippets()["guide-connect-schema"];
    assert.ok(
      snippet.code.startsWith("//// Typed schema for the tutorial retro board."),
      "the listing must open with the module documentation",
    );
    assert.match(snippet.code, /pub fn title\(\)/);
    assert.match(snippet.code, /pub fn notes\(\)/);
    assert.match(snippet.code, /pub fn votes\(\)/);
  });

  it("keeps every other line of the module, in order", () => {
    const snippet = buildSnippets()["guide-connect-schema"];
    const source = readRepoFile(sourcePaths.retroSchema);
    const kept = source
      .split("\n")
      .filter((line) => !/docs:snippet-(start|end)\s/.test(line));
    const rendered = snippet.code.split("\n");

    for (const line of kept) {
      assert.ok(
        rendered.includes(line),
        `the listing dropped a line of the module: ${JSON.stringify(line)}`,
      );
    }
    // Two directive lines go, and one blank line goes with the seam the
    // formatter leaves around the end directive.
    assert.equal(rendered.length, source.split("\n").length - 3);
  });
});

// ── 3. The registry module agrees with the replication ─────────────────────

describe("registry module", () => {
  const registry = readWebsiteFile("src/data/guide-snippets.ts");

  it("selects the schema module with the whole-file helper", () => {
    assert.match(
      registry,
      /"guide-connect-schema":\s*snippetFromWholeFile\(/,
      "the registry must build the listing with snippetFromWholeFile",
    );
  });

  it("has no literal snippets", () => {
    assert.ok(
      !registry.includes("snippetFromLiteral"),
      "guide-snippets.ts must stay source-backed",
    );
  });

  it("imports exactly the sources its paths name", () => {
    for (const path of Object.values(sourcePaths)) {
      assert.ok(
        registry.includes(`${path}?raw`),
        `guide-snippets.ts has no ?raw import for "${path}"`,
      );
      assert.ok(
        registry.includes(`"${path}"`),
        `guide-snippets.ts has no path entry for "${path}"`,
      );
    }
  });
});

// ── 4. The configuration declares the same snippets ────────────────────────

interface ConfiguredSnippet {
  id: string;
  sourcePath: string;
  language: string;
  markers?: string[];
  wholeFile?: boolean;
}

describe("registry ids agree with the generator configuration", () => {
  const entries = (
    JSON.parse(readWebsiteFile("snippets.json")) as {
      snippets: ConfiguredSnippet[];
    }
  ).snippets;

  for (const id of EXPECTED_IDS) {
    it(`${id} is declared in snippets.json`, () => {
      const entry = entries.find((e) => e.id === id);
      const snippet = buildSnippets()[id];
      assert.ok(entry, `snippets.json has no entry for "${id}"`);
      assert.equal(entry.sourcePath, snippet.sourcePath);
      assert.equal(entry.language, snippet.language);
    });
  }

  it("guide-connect-schema is a whole-file entry with no markers", () => {
    const entry = entries.find((e) => e.id === "guide-connect-schema");
    assert.ok(entry);
    assert.equal(entry.wholeFile, true);
    assert.equal(entry.markers, undefined);
  });
});

// ── 5. The guide sheet reads the listing through the registry ──────────────

describe("the guide sheet reads the listing through the registry", () => {
  const page = readWebsiteFile("src/pages/guide/connect.astro");

  it("connect.astro has no ?raw import of the schema module", () => {
    assert.ok(
      !page.includes("document_schema.gleam?raw"),
      "connect.astro must read the schema listing through the registry",
    );
  });

  it("connect.astro reads guide-connect-schema from the registry", () => {
    assert.match(page, /guideSnippets\["guide-connect-schema"\]/);
  });

  it("the removed marker-stripping helper has no callers left", () => {
    const lib = readWebsiteFile("src/lib/snippet.ts");
    assert.ok(
      !lib.includes("sourceWithoutMarkers"),
      "sourceWithoutMarkers is replaced by snippetFromWholeFile",
    );
    assert.ok(!page.includes("sourceWithoutMarkers"));
  });
});
