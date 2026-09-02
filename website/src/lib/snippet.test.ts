// ──────────────────────────────────────────────────────────────────────────
// Tests for the snippet model and the generated-manifest loader.
//
// The website no longer extracts code from source. `tools/source-snippets`
// does that and writes `src/generated/snippets.json`; this module decodes
// that file, refuses anything malformed, and hands out one snippet per id.
//
// Run: node --strip-types --test src/lib/snippet.test.ts
// ──────────────────────────────────────────────────────────────────────────
import test from "node:test";
import assert from "node:assert/strict";
import {
  decodeManifest,
  isSourceBacked,
  snippetFromLiteral,
  sourceSnippet,
  sourceSnippetIds,
  withSourceUrl,
} from "./snippet.ts";

/** A valid two-entry manifest: one marker range and one whole-file listing. */
function validManifest(): unknown {
  return {
    version: 1,
    snippets: {
      "a-range": {
        code: "let x = 1",
        language: "gleam",
        sourcePath: "src/a.gleam",
        origin: { kind: "source", markers: ["a-range"] },
      },
      "a-file": {
        code: "//// A module.\n",
        language: "gleam",
        sourcePath: "src/b.gleam",
        origin: { kind: "file" },
      },
    },
  };
}

/** The valid manifest with one entry replaced by `entry`. */
function manifestWithEntry(entry: unknown): unknown {
  return { version: 1, snippets: { "a-range": entry } };
}

// ── decodeManifest: valid input ───────────────────────────────────────────

test("decodes a valid manifest into one snippet per id", () => {
  const snippets = decodeManifest(validManifest());
  assert.deepEqual([...snippets.keys()].sort(), ["a-file", "a-range"]);
});

test("decodes a marker entry, markers and all", () => {
  const snippet = decodeManifest(validManifest()).get("a-range");
  assert.ok(snippet);
  assert.equal(snippet.code, "let x = 1");
  assert.equal(snippet.language, "gleam");
  assert.equal(snippet.sourcePath, "src/a.gleam");
  assert.equal(snippet.sourceUrl, undefined);
  assert.deepEqual(snippet.origin, { kind: "source", markers: ["a-range"] });
});

test("decodes a whole-file entry as a file origin", () => {
  const snippet = decodeManifest(validManifest()).get("a-file");
  assert.ok(snippet);
  assert.deepEqual(snippet.origin, { kind: "file" });
  assert.ok(isSourceBacked(snippet));
});

test("decodes an empty snippet set — a manifest with no entries is valid", () => {
  assert.equal(decodeManifest({ version: 1, snippets: {} }).size, 0);
});

// ── decodeManifest: the document ──────────────────────────────────────────

test("rejects a manifest that is not an object", () => {
  for (const value of [null, 1, "manifest", [], undefined]) {
    assert.throws(() => decodeManifest(value), /snippet manifest/);
  }
});

test("rejects an unsupported version", () => {
  assert.throws(
    () => decodeManifest({ version: 2, snippets: {} }),
    /version/,
  );
});

test("rejects a missing or non-numeric version", () => {
  assert.throws(() => decodeManifest({ snippets: {} }), /version/);
  assert.throws(() => decodeManifest({ version: "1", snippets: {} }), /version/);
});

test("rejects a missing snippets object", () => {
  assert.throws(() => decodeManifest({ version: 1 }), /snippets/);
});

test("rejects a snippets array — entries are keyed by id", () => {
  assert.throws(() => decodeManifest({ version: 1, snippets: [] }), /snippets/);
});

// ── decodeManifest: entries ───────────────────────────────────────────────

test("rejects an entry that is not an object", () => {
  assert.throws(() => decodeManifest(manifestWithEntry("let x = 1")), /a-range/);
});

test("rejects a missing or non-string field", () => {
  const base = {
    code: "let x = 1",
    language: "gleam",
    sourcePath: "src/a.gleam",
    origin: { kind: "source", markers: ["a-range"] },
  };
  for (const field of ["code", "language", "sourcePath"]) {
    const missing: Record<string, unknown> = { ...base };
    delete missing[field];
    assert.throws(() => decodeManifest(manifestWithEntry(missing)), new RegExp(field));

    const wrongType = { ...base, [field]: 12 };
    assert.throws(() => decodeManifest(manifestWithEntry(wrongType)), new RegExp(field));
  }
});

test("rejects an empty field — a blank citation is not a citation", () => {
  const base = {
    code: "let x = 1",
    language: "gleam",
    sourcePath: "src/a.gleam",
    origin: { kind: "source", markers: ["a-range"] },
  };
  for (const field of ["code", "language", "sourcePath"]) {
    assert.throws(
      () => decodeManifest(manifestWithEntry({ ...base, [field]: "   " })),
      new RegExp(field),
    );
  }
});

test("names the id of the entry it rejects", () => {
  assert.throws(
    () => decodeManifest({ version: 1, snippets: { "guide-x": { code: 1 } } }),
    /guide-x/,
  );
});

// ── decodeManifest: origins ───────────────────────────────────────────────

test("rejects an unknown origin kind", () => {
  const entry = {
    code: "let x = 1",
    language: "gleam",
    sourcePath: "src/a.gleam",
    origin: { kind: "definition", heads: ["pub fn a("] },
  };
  assert.throws(() => decodeManifest(manifestWithEntry(entry)), /origin/);
});

test("rejects a literal origin — the manifest holds source-backed code only", () => {
  const entry = {
    code: "let x = 1",
    language: "gleam",
    sourcePath: "src/a.gleam",
    origin: { kind: "literal" },
  };
  assert.throws(() => decodeManifest(manifestWithEntry(entry)), /origin/);
});

test("rejects a missing origin", () => {
  const entry = { code: "let x = 1", language: "gleam", sourcePath: "src/a.gleam" };
  assert.throws(() => decodeManifest(manifestWithEntry(entry)), /origin/);
});

test("rejects a source origin with no markers", () => {
  const base = { code: "let x = 1", language: "gleam", sourcePath: "src/a.gleam" };
  for (const origin of [
    { kind: "source" },
    { kind: "source", markers: [] },
    { kind: "source", markers: "a-range" },
    { kind: "source", markers: [1] },
    { kind: "source", markers: [" "] },
  ]) {
    assert.throws(
      () => decodeManifest(manifestWithEntry({ ...base, origin })),
      /markers/,
    );
  }
});

test("rejects a file origin that also names markers", () => {
  const entry = {
    code: "//// A module.\n",
    language: "gleam",
    sourcePath: "src/b.gleam",
    origin: { kind: "file", markers: ["a-range"] },
  };
  assert.throws(() => decodeManifest(manifestWithEntry(entry)), /markers/);
});

// ── sourceSnippet ─────────────────────────────────────────────────────────

test("sourceSnippet returns the generated entry for a known id", () => {
  const snippet = sourceSnippet("homepage-beam");
  assert.match(snippet.code, /watershed_beam\.connect/);
  assert.equal(snippet.language, "gleam");
  assert.equal(snippet.sourcePath, "examples/dice_cli/src/dice_cli.gleam");
  assert.deepEqual(snippet.origin, { kind: "source", markers: ["homepage-beam"] });
  assert.equal(snippet.sourceUrl, undefined);
});

test("sourceSnippet throws on an unknown id, and names it", () => {
  assert.throws(
    () => sourceSnippet("guide-connect-invented"),
    /guide-connect-invented/,
  );
});

test("sourceSnippet hands out a frozen snippet — no caller may edit the manifest", () => {
  const snippet = sourceSnippet("homepage-beam");
  assert.ok(Object.isFrozen(snippet));
});

test("sourceSnippetIds lists every generated id", () => {
  const ids = sourceSnippetIds();
  assert.ok(ids.includes("homepage-beam"));
  assert.ok(ids.includes("guide-connect-schema"));
  assert.deepEqual(ids, [...ids].sort(), "ids are listed in a stable order");
});

test("every generated snippet is source-backed and shows no directive", () => {
  for (const id of sourceSnippetIds()) {
    const snippet = sourceSnippet(id);
    assert.ok(isSourceBacked(snippet), `${id} is not source-backed`);
    assert.ok(snippet.code.trim().length > 0, `${id} has empty code`);
    assert.ok(
      !snippet.code.includes("docs:snippet-"),
      `${id} shows a marker directive to the reader`,
    );
  }
});

// ── snippetFromLiteral ────────────────────────────────────────────────────

test("snippetFromLiteral populates all Snippet fields", () => {
  const snippet = snippetFromLiteral(
    "let x = 1",
    "gleam",
    "src/foo.gleam",
    "https://example.com/foo.gleam",
  );
  assert.equal(snippet.code, "let x = 1");
  assert.equal(snippet.language, "gleam");
  assert.equal(snippet.sourcePath, "src/foo.gleam");
  assert.equal(snippet.sourceUrl, "https://example.com/foo.gleam");
  assert.deepEqual(snippet.origin, { kind: "literal" });
  assert.ok(!isSourceBacked(snippet));
});

test("snippetFromLiteral: sourceUrl is undefined when omitted", () => {
  assert.equal(
    snippetFromLiteral("let x = 1", "gleam", "src/foo.gleam").sourceUrl,
    undefined,
  );
});

test("snippetFromLiteral rejects an empty field", () => {
  assert.throws(() => snippetFromLiteral("", "gleam", "src/foo.gleam"), /code/);
  assert.throws(() => snippetFromLiteral("let x = 1", "", "src/foo.gleam"), /language/);
  assert.throws(() => snippetFromLiteral("let x = 1", "gleam", " "), /sourcePath/);
});

// ── withSourceUrl ─────────────────────────────────────────────────────────

test("withSourceUrl adds a link and changes nothing else", () => {
  const snippet = sourceSnippet("homepage-beam");
  const linked = withSourceUrl(snippet, "https://example.com/dice_cli.gleam");
  assert.equal(linked.sourceUrl, "https://example.com/dice_cli.gleam");
  assert.equal(linked.code, snippet.code);
  assert.equal(linked.language, snippet.language);
  assert.equal(linked.sourcePath, snippet.sourcePath);
  assert.deepEqual(linked.origin, snippet.origin);
});

test("withSourceUrl leaves the snippet it was given alone", () => {
  const snippet = snippetFromLiteral("let x = 1", "gleam", "src/foo.gleam");
  withSourceUrl(snippet, "https://example.com/foo.gleam");
  assert.equal(snippet.sourceUrl, undefined);
});

test("withSourceUrl works on a frozen generated snippet", () => {
  const linked = withSourceUrl(sourceSnippet("homepage-beam"), "https://example.com/x");
  assert.equal(linked.sourceUrl, "https://example.com/x");
});

test("withSourceUrl rejects an empty url", () => {
  const snippet = snippetFromLiteral("let x = 1", "gleam", "src/foo.gleam");
  assert.throws(() => withSourceUrl(snippet, " "), /sourceUrl/);
});

// ── isSourceBacked ────────────────────────────────────────────────────────

test("isSourceBacked separates generated code from a hand-written literal", () => {
  assert.ok(isSourceBacked(sourceSnippet("homepage-beam")));
  assert.ok(isSourceBacked(sourceSnippet("guide-connect-schema")));
  assert.ok(
    !isSourceBacked(snippetFromLiteral("echo hi", "sh", "(shell)")),
  );
});
