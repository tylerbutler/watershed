// Tests for the snippet model and extractor.
// Run: node --strip-types --test src/lib/snippet.test.ts
import test from "node:test";
import assert from "node:assert/strict";
import { snippetFromDefinition, snippetFromMarker } from "./snippet.ts";
import { excerpt } from "./excerpt.ts";

// ── snippetFromDefinition ─────────────────────────────────────────────────

test("extracts a whole top-level definition", () => {
  const source = "pub fn add(a: Int, b: Int) -> Int {\n  a + b\n}\n";
  const s = snippetFromDefinition(source, "src/math.gleam", "gleam", "pub fn add(");
  assert.equal(s.code, "pub fn add(a: Int, b: Int) -> Int {\n  a + b\n}");
  assert.equal(s.language, "gleam");
  assert.equal(s.sourcePath, "src/math.gleam");
  assert.deepEqual(s.origin, { kind: "definition", heads: ["pub fn add("] });
});

test("includes adjacent comments directly above the definition", () => {
  const source = [
    "// Adds two integers.",
    "pub fn add(a: Int, b: Int) -> Int {",
    "  a + b",
    "}",
    "",
  ].join("\n");
  const s = snippetFromDefinition(source, "src/math.gleam", "gleam", "pub fn add(");
  assert.ok(s.code.startsWith("// Adds two integers.\npub fn add("));
});

test("multi-definition extraction joins results with a blank line", () => {
  const source = [
    "pub fn a() {",
    "  1",
    "}",
    "",
    "pub fn b() {",
    "  2",
    "}",
    "",
  ].join("\n");
  const s = snippetFromDefinition(
    source,
    "src/math.gleam",
    "gleam",
    "pub fn a(",
    "pub fn b(",
  );
  assert.ok(s.code.includes("pub fn a()"));
  assert.ok(s.code.includes("pub fn b()"));
  assert.ok(s.code.includes("}\n\npub fn b()"));
  assert.deepEqual(s.origin, {
    kind: "definition",
    heads: ["pub fn a(", "pub fn b("],
  });
});

test("throws when a definition head is not found", () => {
  const source = "pub fn foo() {\n  1\n}\n";
  assert.throws(
    () => snippetFromDefinition(source, "src/math.gleam", "gleam", "pub fn missing("),
    /no top-level line starts with/,
  );
});

// ── snippetFromMarker ─────────────────────────────────────────────────────

test("extracts a valid named marker range", () => {
  const source = [
    "pub fn main() {",
    "  // snippet:start my-range",
    "  let x = 1",
    "  // snippet:end my-range",
    "}",
  ].join("\n");
  const s = snippetFromMarker(source, "src/main.gleam", "gleam", "my-range");
  assert.equal(s.language, "gleam");
  assert.equal(s.sourcePath, "src/main.gleam");
  assert.deepEqual(s.origin, { kind: "marker", name: "my-range" });
  assert.equal(s.code, "let x = 1");
});

test("normalizes indentation in marker ranges", () => {
  const source = [
    "fn main() {",
    "  // snippet:start inner",
    "  let x = 1",
    "  let y = 2",
    "  // snippet:end inner",
    "}",
  ].join("\n");
  const s = snippetFromMarker(source, "src/main.gleam", "gleam", "inner");
  assert.equal(s.code, "let x = 1\nlet y = 2");
});

test("preserves source comments inside the marker range", () => {
  const source = [
    "// snippet:start with-comment",
    "let x = 1",
    "// This is an inline comment.",
    "let y = 2",
    "// snippet:end with-comment",
  ].join("\n");
  const s = snippetFromMarker(source, "src/main.gleam", "gleam", "with-comment");
  assert.ok(s.code.includes("// This is an inline comment."));
  assert.ok(s.code.includes("let x = 1"));
  assert.ok(s.code.includes("let y = 2"));
});

// ── Rejection cases ───────────────────────────────────────────────────────

test("rejects missing start marker", () => {
  const source = "// snippet:end my-range\nlet x = 1\n";
  assert.throws(
    () => snippetFromMarker(source, "src/main.gleam", "gleam", "my-range"),
    /no start marker/,
  );
});

test("rejects missing end marker", () => {
  const source = "// snippet:start my-range\nlet x = 1\n";
  assert.throws(
    () => snippetFromMarker(source, "src/main.gleam", "gleam", "my-range"),
    /no end marker/,
  );
});

test("rejects duplicate start marker", () => {
  const source = [
    "// snippet:start foo",
    "let a = 1",
    "// snippet:end foo",
    "// snippet:start foo",
    "let b = 2",
    "// snippet:end foo",
  ].join("\n");
  assert.throws(
    () => snippetFromMarker(source, "src/main.gleam", "gleam", "foo"),
    /duplicate start/,
  );
});

test("rejects duplicate end marker", () => {
  const source = [
    "// snippet:start foo",
    "let a = 1",
    "// snippet:end foo",
    "// snippet:end foo",
  ].join("\n");
  assert.throws(
    () => snippetFromMarker(source, "src/main.gleam", "gleam", "foo"),
    /duplicate end/,
  );
});

test("rejects reversed markers (end before start)", () => {
  const source = [
    "// snippet:end foo",
    "let a = 1",
    "// snippet:start foo",
  ].join("\n");
  assert.throws(
    () => snippetFromMarker(source, "src/main.gleam", "gleam", "foo"),
    /comes before start/,
  );
});

test("rejects nested start marker inside a range", () => {
  const source = [
    "// snippet:start outer",
    "let a = 1",
    "// snippet:start inner",
    "let b = 2",
    "// snippet:end inner",
    "// snippet:end outer",
  ].join("\n");
  assert.throws(
    () => snippetFromMarker(source, "src/main.gleam", "gleam", "outer"),
    /nested start/,
  );
});

test("rejects mismatched end marker inside a range", () => {
  const source = [
    "// snippet:start foo",
    "let a = 1",
    "// snippet:end bar",
    "let b = 2",
    "// snippet:end foo",
  ].join("\n");
  assert.throws(
    () => snippetFromMarker(source, "src/main.gleam", "gleam", "foo"),
    /mismatched end/,
  );
});

test("rejects an empty marker range", () => {
  const source = ["// snippet:start empty", "// snippet:end empty"].join("\n");
  assert.throws(
    () => snippetFromMarker(source, "src/main.gleam", "gleam", "empty"),
    /empty range/,
  );
});

// ── excerpt() compatibility wrapper ──────────────────────────────────────

test("excerpt() returns the same code as snippetFromDefinition()", () => {
  const source = "pub fn foo() {\n  1\n}\n";
  const viaExcerpt = excerpt(source, "pub fn foo(");
  const viaSnippet = snippetFromDefinition(source, "", "gleam", "pub fn foo(").code;
  assert.equal(viaExcerpt, viaSnippet);
});
