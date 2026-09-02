// ──────────────────────────────────────────────────────────────────────────
// Drift gates — dependency-free checks that fail when source-backed
// snippets drift from the compiled source they claim to show.
//
// Each gate catches one category of drift. Negative tests prove the gate
// fires for fabricated drift; positive tests prove the codebase is clean.
//
// Run: node --strip-types --test src/data/drift-gates.test.ts
// ──────────────────────────────────────────────────────────────────────────
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync, readdirSync } from "node:fs";
import { resolve, dirname, relative, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const websiteRoot = resolve(__dirname, "../..");
const repoRoot = resolve(__dirname, "../../..");

// ══════════════════════════════════════════════════════════════════════════
// Policy: explicit allowlists
//
// Update these when adding new snippet sources, markers, or pages that
// legitimately use literal Gleam. A missing entry fails the gate — that
// is the point.
// ══════════════════════════════════════════════════════════════════════════

/** Pages allowed to use snippetFromLiteral with "gleam" language. Each entry
 *  is illustrative Gleam without compiled source — a comparison, a simplified
 *  example, or a hypothetical that would be dishonest to extract. */
const LITERAL_GLEAM_ALLOWLIST = new Set([
  "src/pages/guide/connect.astro",    // watershed_beam comparison
  "src/pages/guide/votes.astro",      // lossy counter illustration
  "src/pages/guide/testing.astro",    // scripted delivery illustration
  "src/pages/runtime/presence.astro", // presence config illustration
]);

/** Directories (repo-relative) whose .gleam files may contain doc markers. */
const MARKER_SOURCE_DIRS = [
  "examples",
  "tools/website-samples",
  "src",
  "watershed_lustre/src",
];

/** Files that contain snippet descriptors via ?raw imports + extractor calls.
 *  Registries are the centralized source; pages use direct extraction. */
const SNIPPET_DESCRIPTOR_FILES = [
  // Centralized registries
  "src/data/practice-snippets.ts",
  "src/data/standalone-snippets.ts",
  // Pages with direct extraction
  "src/pages/foundations/topology.astro",
  "src/pages/foundations/schema.astro",
  "src/pages/foundations/lifecycle.astro",
  "src/pages/guide/connect.astro",
  "src/pages/guide/notes.astro",
  "src/pages/guide/votes.astro",
  "src/pages/guide/presence.astro",
  "src/pages/guide/testing.astro",
];

// ══════════════════════════════════════════════════════════════════════════
// Helpers
// ══════════════════════════════════════════════════════════════════════════

/** Recursively collect all .gleam files under a directory, skipping build/. */
function findGleamFiles(dir: string): string[] {
  const results: string[] = [];
  if (!existsSync(dir)) return results;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory() && entry.name !== "build" && entry.name !== "node_modules") {
      results.push(...findGleamFiles(full));
    } else if (entry.name.endsWith(".gleam")) {
      results.push(full);
    }
  }
  return results;
}

/** Parse docs:snippet-start/end markers from source text. */
function parseMarkers(content: string): {
  starts: Map<string, number[]>;
  ends: Map<string, number[]>;
} {
  const starts = new Map<string, number[]>();
  const ends = new Map<string, number[]>();
  const lines = content.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const sm = /^\s*\/\/\s*docs:snippet-start\s+(\S+)\s*$/.exec(lines[i]);
    const em = /^\s*\/\/\s*docs:snippet-end\s+(\S+)\s*$/.exec(lines[i]);
    if (sm) {
      const id = sm[1];
      if (!starts.has(id)) starts.set(id, []);
      starts.get(id)!.push(i + 1);
    }
    if (em) {
      const id = em[1];
      if (!ends.has(id)) ends.set(id, []);
      ends.get(id)!.push(i + 1);
    }
  }
  return { starts, ends };
}

/** Extract ?raw import paths from source, resolved to repo-relative paths. */
function extractRawImportPaths(source: string, fileAbsDir: string): string[] {
  const paths: string[] = [];
  const re = /from\s+["']([^"']+)\?raw["']/g;
  let m;
  while ((m = re.exec(source)) !== null) {
    const absPath = resolve(fileAbsDir, m[1]);
    paths.push(relative(repoRoot, absPath));
  }
  return paths;
}

/** Extract marker IDs from snippetFromMarker(..., "name") calls. */
function extractMarkerRefs(source: string): string[] {
  const ids: string[] = [];
  // The marker ID is the last string argument before the closing paren.
  // [\s\S]*? handles multiline calls.
  const re = /snippetFromMarker\s*\([\s\S]*?,\s*["']([^"']+)["']\s*,?\s*\)/g;
  let m;
  while ((m = re.exec(source)) !== null) {
    ids.push(m[1]);
  }
  return ids;
}

/** Extract values from `const paths = { ... } as const;` blocks. */
function extractPathsObjectValues(source: string): string[] {
  const block = source.match(/const paths\s*=\s*\{([^}]+)\}\s*as const/s);
  if (!block) return [];
  const values: string[] = [];
  const re = /:\s*["']([^"']*)["']/g;
  let m;
  while ((m = re.exec(block[1])) !== null) {
    values.push(m[1]);
  }
  return values;
}

/**
 * True when source has a snippetFromLiteral call whose *language argument*
 * (the second positional arg) is "gleam".
 *
 * The previous regex `snippetFromLiteral\([\s\S]*?, "gleam"` was greedy
 * across calls — a non-Gleam literal followed later by an unrelated
 * `"gleam"` string would false-positive.  This scanner finds each
 * `snippetFromLiteral(` occurrence, walks parentheses/template-literal
 * depth to isolate the first argument, then inspects the second argument
 * token directly.
 */
function hasLiteralGleamCall(source: string): boolean {
  const callRe = /snippetFromLiteral\s*\(/g;
  let callMatch;
  while ((callMatch = callRe.exec(source)) !== null) {
    const argStart = callMatch.index + callMatch[0].length;
    if (isGleamSecondArg(source, argStart)) return true;
  }
  return false;
}

/**
 * Starting just after the opening `(` of a snippetFromLiteral call,
 * skip the first argument (template literal, string, or identifier)
 * and return true when the second argument is the string "gleam" or 'gleam'.
 */
function isGleamSecondArg(source: string, pos: number): boolean {
  const len = source.length;
  let i = skipWhitespace(source, pos, len);
  // Skip the first argument — may be a template literal, quoted string, or identifier.
  i = skipExpression(source, i, len);
  if (i >= len) return false;
  // Expect a comma between the first and second arguments.
  i = skipWhitespace(source, i, len);
  if (i >= len || source[i] !== ",") return false;
  i = skipWhitespace(source, i + 1, len);
  // The second argument should be a string literal.
  if (i >= len) return false;
  const q = source[i];
  if (q !== '"' && q !== "'") return false;
  // Read the string content up to the matching close quote.
  let str = "";
  for (let j = i + 1; j < len; j++) {
    if (source[j] === "\\") { j++; continue; }
    if (source[j] === q) break;
    str += source[j];
  }
  return str === "gleam";
}

/** Skip whitespace and line breaks. */
function skipWhitespace(s: string, i: number, len: number): number {
  while (i < len && /\s/.test(s[i])) i++;
  return i;
}

/**
 * Skip one expression: template literal, quoted string, or a
 * balanced parenthesized/bracketed sub-expression, or a plain
 * identifier token. Returns the index after the expression.
 */
function skipExpression(source: string, start: number, len: number): number {
  if (start >= len) return start;
  const ch = source[start];
  // Template literal
  if (ch === "`") return skipTemplateLiteral(source, start + 1, len);
  // Quoted string
  if (ch === '"' || ch === "'") return skipString(source, start, len);
  // Parenthesized or bracketed sub-expression
  if (ch === "(") return skipBalanced(source, start, len, "(", ")");
  if (ch === "[") return skipBalanced(source, start, len, "[", "]");
  // Identifier, number, or dotted expression — stop at comma or closing paren
  let i = start;
  while (i < len) {
    const c = source[i];
    if (c === "," || c === ")") return i;
    // Nested call inside argument (e.g., fn(x))
    if (c === "(") { i = skipBalanced(source, i, len, "(", ")"); continue; }
    if (c === "`") { i = skipTemplateLiteral(source, i + 1, len); continue; }
    if (c === '"' || c === "'") { i = skipString(source, i, len); continue; }
    i++;
  }
  return i;
}

function skipString(source: string, start: number, len: number): number {
  const q = source[start];
  let i = start + 1;
  while (i < len) {
    if (source[i] === "\\") { i += 2; continue; }
    if (source[i] === q) return i + 1;
    i++;
  }
  return i;
}

function skipTemplateLiteral(source: string, start: number, len: number): number {
  let i = start;
  while (i < len) {
    if (source[i] === "\\") { i += 2; continue; }
    if (source[i] === "`") return i + 1;
    if (source[i] === "$" && i + 1 < len && source[i + 1] === "{") {
      // Template expression — skip balanced braces
      i = skipBalanced(source, i + 1, len, "{", "}");
      continue;
    }
    i++;
  }
  return i;
}

function skipBalanced(
  source: string, start: number, len: number,
  open: string, close: string,
): number {
  let depth = 0;
  let i = start;
  while (i < len) {
    const c = source[i];
    if (c === open) depth++;
    else if (c === close) { depth--; if (depth === 0) return i + 1; }
    else if (c === "`") { i = skipTemplateLiteral(source, i + 1, len); continue; }
    else if (c === '"' || c === "'") { i = skipString(source, i, len); continue; }
    else if (c === "\\") { i += 2; continue; }
    i++;
  }
  return i;
}

/** Collect all .astro pages under src/pages/. */
function findAstroPages(): string[] {
  const pagesDir = resolve(websiteRoot, "src/pages");
  const results: string[] = [];
  function walk(dir: string) {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name.endsWith(".astro")) results.push(full);
    }
  }
  walk(pagesDir);
  return results;
}

/** Files that are explicitly exempt from the scope-wide raw-Gleam and
 *  literal-Gleam gates — the snippet library itself, test files, and
 *  the drift gates test. */
const GATE_EXEMPT_PATTERNS = [
  /\.test\.ts$/,          // test suites
  /drift-gates\.test\./,  // this file
  /\/lib\/snippet\.ts$/,  // the extractor implementation
  /\/lib\/snippet-markers\.test\./,  // marker test suite
];

/** All authored website source modules: src/**\/*.astro and src/**\/*.ts,
 *  minus test files and the extractor itself. */
function findAllAuthoredModules(): string[] {
  const srcDir = resolve(websiteRoot, "src");
  const results: string[] = [];
  function walk(dir: string) {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = join(dir, entry.name);
      if (entry.isDirectory() && entry.name !== "node_modules") {
        walk(full);
      } else if (entry.name.endsWith(".astro") || entry.name.endsWith(".ts")) {
        const rel = relative(websiteRoot, full);
        if (!GATE_EXEMPT_PATTERNS.some((p) => p.test(rel))) {
          results.push(full);
        }
      }
    }
  }
  walk(srcDir);
  return results;
}

/**
 * Files that are allowed to import from the snippet library or use
 * ?raw Gleam imports. Anything not in this set or in
 * LITERAL_GLEAM_ALLOWLIST that touches raw Gleam trips the gate.
 */
const ALLOWED_SNIPPET_USERS = new Set([
  ...SNIPPET_DESCRIPTOR_FILES,
  ...LITERAL_GLEAM_ALLOWLIST,
]);

// ══════════════════════════════════════════════════════════════════════════
// Pre-computed data: markers from Gleam sources, refs from descriptor files
// ══════════════════════════════════════════════════════════════════════════

/** Marker occurrence in a single file. */
interface MarkerOccurrence {
  file: string;
  startLines: number[];
  endLines: number[];
}

/** All markers found across all .gleam source files, per (id, file) pair. */
function scanAllMarkers(): {
  byId: Map<string, MarkerOccurrence[]>;
  diagnostics: string[];
} {
  // Collect per-file occurrences: Map<id, MarkerOccurrence[]>
  const byId = new Map<string, MarkerOccurrence[]>();
  const diagnostics: string[] = [];

  for (const dir of MARKER_SOURCE_DIRS) {
    const absDir = resolve(repoRoot, dir);
    for (const file of findGleamFiles(absDir)) {
      const content = readFileSync(file, "utf-8");
      const { starts, ends } = parseMarkers(content);
      const repoFile = relative(repoRoot, file);

      // Collect all IDs seen in this file
      const idsInFile = new Set([...starts.keys(), ...ends.keys()]);
      for (const id of idsInFile) {
        const startLines = starts.get(id) ?? [];
        const endLines = ends.get(id) ?? [];
        if (!byId.has(id)) byId.set(id, []);
        byId.get(id)!.push({ file: repoFile, startLines, endLines });
      }
    }
  }

  // Validate per-id invariants
  for (const [id, occurrences] of byId) {
    const allStarts = occurrences.flatMap((o) => o.startLines);
    const allEnds = occurrences.flatMap((o) => o.endLines);
    const filesWithStarts = occurrences.filter((o) => o.startLines.length > 0).map((o) => o.file);
    const filesWithEnds = occurrences.filter((o) => o.endLines.length > 0).map((o) => o.file);

    // Reject start/end split across files
    if (filesWithStarts.length > 0 && filesWithEnds.length > 0) {
      const startFileSet = new Set(filesWithStarts);
      const endFileSet = new Set(filesWithEnds);
      const startOnly = filesWithStarts.filter((f) => !endFileSet.has(f));
      const endOnly = filesWithEnds.filter((f) => !startFileSet.has(f));
      if (startOnly.length > 0 || endOnly.length > 0) {
        diagnostics.push(
          `marker "${id}": start/end split across files — start in [${startOnly.join(", ")}], end in [${endOnly.join(", ")}]`,
        );
      }
    }

    // Reject end-before-start within a single file
    for (const occ of occurrences) {
      if (occ.startLines.length === 1 && occ.endLines.length === 1) {
        if (occ.endLines[0] <= occ.startLines[0]) {
          diagnostics.push(
            `marker "${id}" in ${occ.file}: end (line ${occ.endLines[0]}) before start (line ${occ.startLines[0]})`,
          );
        }
      }
    }
  }

  return { byId, diagnostics };
}

/** All marker IDs referenced by snippet descriptor files (registries + pages). */
function collectMarkerReferences(): Set<string> {
  const refs = new Set<string>();

  for (const file of SNIPPET_DESCRIPTOR_FILES) {
    const absPath = resolve(websiteRoot, file);
    if (!existsSync(absPath)) continue;
    const source = readFileSync(absPath, "utf-8");
    for (const id of extractMarkerRefs(source)) {
      refs.add(id);
    }
  }

  return refs;
}

// ══════════════════════════════════════════════════════════════════════════
// Gate 1: Referenced source paths exist
// ══════════════════════════════════════════════════════════════════════════

describe("Gate: source paths exist", () => {
  describe("positive — all declared paths resolve to real files", () => {
    for (const file of SNIPPET_DESCRIPTOR_FILES) {
      it(`${file}: every ?raw import resolves`, () => {
        const absPath = resolve(websiteRoot, file);
        const source = readFileSync(absPath, "utf-8");
        const fileDir = dirname(absPath);
        const importPaths = extractRawImportPaths(source, fileDir);

        assert.ok(importPaths.length > 0, `${file} has no ?raw imports`);

        for (const p of importPaths) {
          const abs = resolve(repoRoot, p);
          assert.ok(
            existsSync(abs),
            `${file}: ?raw import path "${p}" does not exist at repo root`,
          );
        }
      });
    }

    for (const file of ["src/data/practice-snippets.ts", "src/data/standalone-snippets.ts"]) {
      it(`${file}: every paths object value is a real file`, () => {
        const absPath = resolve(websiteRoot, file);
        const source = readFileSync(absPath, "utf-8");
        const pathValues = extractPathsObjectValues(source);

        assert.ok(pathValues.length > 0, `${file} has no paths object`);

        for (const p of pathValues) {
          const abs = resolve(repoRoot, p);
          assert.ok(
            existsSync(abs),
            `${file}: sourcePath "${p}" does not exist at repo root`,
          );
        }
      });
    }
  });

  describe("negative — catches a missing source path", () => {
    it("rejects a nonexistent path", () => {
      const fakePath = "examples/nonexistent_project/src/main.gleam";
      const abs = resolve(repoRoot, fakePath);
      assert.ok(!existsSync(abs), "fake path should not exist");
    });

    it("validates repo root is correct", () => {
      assert.ok(
        existsSync(resolve(repoRoot, "gleam.toml")),
        "repo root should contain gleam.toml",
      );
    });
  });
});

// ══════════════════════════════════════════════════════════════════════════
// Gate 2: Marker integrity — unique, well-formed, no orphans
// ══════════════════════════════════════════════════════════════════════════

describe("Gate: marker integrity", () => {
  const { byId: allMarkers, diagnostics: markerDiagnostics } = scanAllMarkers();
  const allRefs = collectMarkerReferences();

  describe("positive — no structural marker defects (split-file, reversed)", () => {
    it("no cross-file or reversed marker diagnostics", () => {
      assert.deepEqual(
        markerDiagnostics,
        [],
        `marker structural defects:\n${markerDiagnostics.join("\n")}`,
      );
    });
  });

  describe("positive — every marker ID has exactly one start and one end", () => {
    it("at least one marker exists", () => {
      assert.ok(allMarkers.size > 0, "no markers found in source");
    });

    for (const [id, occurrences] of allMarkers) {
      const totalStarts = occurrences.reduce((s, o) => s + o.startLines.length, 0);
      const totalEnds = occurrences.reduce((s, o) => s + o.endLines.length, 0);
      const files = occurrences.map((o) => o.file).join(", ");

      it(`marker "${id}" has exactly one start`, () => {
        assert.equal(
          totalStarts,
          1,
          `"${id}" has ${totalStarts} start marker(s) in ${files}`,
        );
      });

      it(`marker "${id}" has exactly one end`, () => {
        assert.equal(
          totalEnds,
          1,
          `"${id}" has ${totalEnds} end marker(s) in ${files}`,
        );
      });
    }
  });

  describe("positive — every referenced marker exists in source", () => {
    for (const id of allRefs) {
      it(`referenced marker "${id}" exists in Gleam source`, () => {
        assert.ok(
          allMarkers.has(id),
          `marker "${id}" is referenced by a descriptor but not found in any .gleam source`,
        );
      });
    }
  });

  describe("positive — no orphan markers in source", () => {
    for (const [id] of allMarkers) {
      it(`marker "${id}" is referenced by a descriptor file`, () => {
        assert.ok(
          allRefs.has(id),
          `marker "${id}" exists in source but is not referenced by any descriptor file — remove it or add a reference`,
        );
      });
    }
  });

  describe("negative — detects malformed markers", () => {
    it("catches duplicate start markers", () => {
      const content = [
        "// docs:snippet-start test-dup",
        "let a = 1",
        "// docs:snippet-start test-dup",
        "let b = 2",
        "// docs:snippet-end test-dup",
      ].join("\n");
      const { starts } = parseMarkers(content);
      assert.equal(starts.get("test-dup")?.length, 2, "should detect 2 starts");
    });

    it("catches duplicate end markers", () => {
      const content = [
        "// docs:snippet-start test-dup-end",
        "let a = 1",
        "// docs:snippet-end test-dup-end",
        "// docs:snippet-end test-dup-end",
      ].join("\n");
      const { ends } = parseMarkers(content);
      assert.equal(ends.get("test-dup-end")?.length, 2, "should detect 2 ends");
    });

    it("catches missing end marker", () => {
      const content = [
        "// docs:snippet-start orphan-start",
        "let a = 1",
      ].join("\n");
      const { starts, ends } = parseMarkers(content);
      assert.equal(starts.get("orphan-start")?.length, 1);
      assert.ok(!ends.has("orphan-start"), "should have no end marker");
    });

    it("catches missing start marker", () => {
      const content = [
        "let a = 1",
        "// docs:snippet-end orphan-end",
      ].join("\n");
      const { starts, ends } = parseMarkers(content);
      assert.ok(!starts.has("orphan-end"), "should have no start marker");
      assert.equal(ends.get("orphan-end")?.length, 1);
    });

    it("detects start/end split across files", () => {
      // Simulate: file-a.gleam has start only, file-b.gleam has end only
      const byId = new Map<string, MarkerOccurrence[]>();
      byId.set("split-id", [
        { file: "file-a.gleam", startLines: [5], endLines: [] },
        { file: "file-b.gleam", startLines: [], endLines: [10] },
      ]);
      // Run the same validation logic manually
      const occ = byId.get("split-id")!;
      const filesWithStarts = occ.filter((o) => o.startLines.length > 0).map((o) => o.file);
      const filesWithEnds = occ.filter((o) => o.endLines.length > 0).map((o) => o.file);
      const startFileSet = new Set(filesWithStarts);
      const endFileSet = new Set(filesWithEnds);
      const startOnly = filesWithStarts.filter((f) => !endFileSet.has(f));
      const endOnly = filesWithEnds.filter((f) => !startFileSet.has(f));
      assert.ok(startOnly.length > 0, "should detect start in file without end");
      assert.ok(endOnly.length > 0, "should detect end in file without start");
    });

    it("detects end-before-start (reversed pair)", () => {
      const content = [
        "// docs:snippet-end reversed-id",
        "let a = 1",
        "// docs:snippet-start reversed-id",
      ].join("\n");
      const { starts, ends } = parseMarkers(content);
      const startLines = starts.get("reversed-id") ?? [];
      const endLines = ends.get("reversed-id") ?? [];
      assert.equal(startLines.length, 1);
      assert.equal(endLines.length, 1);
      assert.ok(endLines[0] < startLines[0], "end should be before start");
    });
  });
});

// ══════════════════════════════════════════════════════════════════════════
// Gate 3: Literal Gleam policy — only allowlisted pages
// ══════════════════════════════════════════════════════════════════════════

describe("Gate: literal Gleam policy", () => {
  describe("positive — no unapproved literal Gleam in any authored module", () => {
    const modules = findAllAuthoredModules();

    it("scans at least 40 authored modules", () => {
      assert.ok(modules.length >= 40, `only found ${modules.length} modules`);
    });

    for (const absModule of modules) {
      const relModule = relative(websiteRoot, absModule);

      it(`${relModule}: no unapproved snippetFromLiteral("gleam")`, () => {
        const source = readFileSync(absModule, "utf-8");
        if (hasLiteralGleamCall(source)) {
          assert.ok(
            LITERAL_GLEAM_ALLOWLIST.has(relModule),
            `${relModule} uses snippetFromLiteral with "gleam" but is not in LITERAL_GLEAM_ALLOWLIST`,
          );
        }
      });
    }
  });

  describe("positive — allowlisted pages actually use literal Gleam", () => {
    for (const page of LITERAL_GLEAM_ALLOWLIST) {
      it(`${page} contains a snippetFromLiteral("gleam") call`, () => {
        const abs = resolve(websiteRoot, page);
        const source = readFileSync(abs, "utf-8");
        assert.ok(
          hasLiteralGleamCall(source),
          `${page} is in the allowlist but has no literal Gleam — remove it from the allowlist`,
        );
      });
    }
  });

  describe("negative — catches disallowed literal Gleam", () => {
    it("detects snippetFromLiteral with gleam language", () => {
      const fake = `const s = snippetFromLiteral(\`import gleam/io\`, "gleam", "fake");`;
      assert.ok(hasLiteralGleamCall(fake), "should detect literal Gleam");
    });

    it("ignores snippetFromLiteral with typescript language", () => {
      const fake = `const s = snippetFromLiteral(\`const x = 1\`, "typescript", "fake");`;
      assert.ok(!hasLiteralGleamCall(fake), "should not flag TypeScript");
    });

    it("ignores snippetFromLiteral with sh language", () => {
      const fake = `const s = snippetFromLiteral(\`echo hello\`, "sh", "fake");`;
      assert.ok(!hasLiteralGleamCall(fake), "should not flag shell");
    });

    it("ignores snippetFromLiteral with toml language", () => {
      const fake = `const s = snippetFromLiteral(gleamToml, "toml", "path");`;
      assert.ok(!hasLiteralGleamCall(fake), "should not flag TOML");
    });

    it("ignores snippetFromLiteral with text language", () => {
      const fake = `const s = snippetFromLiteral(\`tree output\`, "text", "fake");`;
      assert.ok(!hasLiteralGleamCall(fake), "should not flag text");
    });

    it("detects multiline snippetFromLiteral with gleam", () => {
      const fake = `const s = snippetFromLiteral(
  \`import gleam/io
pub fn main() { io.println("hi") }\`,
  "gleam",
  "(illustrative)",
);`;
      assert.ok(hasLiteralGleamCall(fake), "should detect multiline literal Gleam");
    });

    it("does not false-positive on non-Gleam literal followed by unrelated gleam string", () => {
      // A text literal followed by an unrelated "gleam" mention in a different call or context.
      const fake = `const a = snippetFromLiteral(\`echo hello\`, "text", "fake");
const b = "gleam is great";
const c = snippetFromLiteral(\`console.log("hi")\`, "typescript", "other");`;
      assert.ok(!hasLiteralGleamCall(fake), "should not false-positive across calls");
    });

    it("detects gleam in multiline template literal with embedded expressions", () => {
      const fake = `const s = snippetFromLiteral(
  \`import gleam/io
pub fn main() {
  io.println(\${"hello"})
}\`,
  "gleam",
  "(illustrative)",
);`;
      assert.ok(hasLiteralGleamCall(fake), "should detect gleam with template expressions");
    });

    it("catches literal Gleam call in a hypothetical new data module", () => {
      // A new src/data/extra-snippets.ts module with a literal Gleam call
      // must be detected by hasLiteralGleamCall. The scope gate ensures
      // that file would fail if not in the allowlist.
      const fake = `import { snippetFromLiteral } from "../lib/snippet.ts";
export const extra = snippetFromLiteral(\`import gleam/io\nfn main() { io.println("hi") }\`, "gleam", "(illustrative)");`;
      assert.ok(hasLiteralGleamCall(fake), "should catch literal Gleam in new data module");
    });
  });
});

// ══════════════════════════════════════════════════════════════════════════
// Gate 4: Source-backed registries — no literal Gleam in registries
// ══════════════════════════════════════════════════════════════════════════

describe("Gate: registries are source-backed", () => {
  it("practice-snippets.ts has no snippetFromLiteral calls", () => {
    const source = readFileSync(
      resolve(websiteRoot, "src/data/practice-snippets.ts"),
      "utf-8",
    );
    assert.ok(
      !source.includes("snippetFromLiteral"),
      "practice-snippets.ts must not use snippetFromLiteral — all practices are source-backed",
    );
  });

  it("standalone-snippets.ts has no literal Gleam", () => {
    const source = readFileSync(
      resolve(websiteRoot, "src/data/standalone-snippets.ts"),
      "utf-8",
    );
    assert.ok(
      !hasLiteralGleamCall(source),
      "standalone-snippets.ts must not use snippetFromLiteral with 'gleam' — Gleam snippets are source-backed",
    );
  });

  it("standalone-snippets.ts TypeScript literals are allowed", () => {
    const source = readFileSync(
      resolve(websiteRoot, "src/data/standalone-snippets.ts"),
      "utf-8",
    );
    // Verify TS literals exist (they are the legitimate use of snippetFromLiteral)
    assert.ok(
      source.includes('"typescript"'),
      "standalone-snippets.ts should contain TypeScript literals",
    );
  });
});

// ══════════════════════════════════════════════════════════════════════════
// Gate 5: Source-backed descriptors have a displayed source path
// ══════════════════════════════════════════════════════════════════════════

describe("Gate: source-backed descriptors have sourcePath", () => {
  for (const file of ["src/data/practice-snippets.ts", "src/data/standalone-snippets.ts"]) {
    it(`${file}: paths object has no empty values`, () => {
      const source = readFileSync(resolve(websiteRoot, file), "utf-8");
      const values = extractPathsObjectValues(source);

      for (const v of values) {
        assert.ok(v.trim().length > 0, `${file}: empty sourcePath in paths object`);
        assert.ok(
          v.includes("/"),
          `${file}: sourcePath "${v}" does not look like a repo-relative path (no "/")`,
        );
      }
    });
  }

  describe("negative — catches empty or missing sourcePath", () => {
    it("rejects empty string as a valid path", () => {
      const fakeSource = `const paths = { bad: "" } as const;`;
      const values = extractPathsObjectValues(fakeSource);
      assert.equal(values.length, 1);
      assert.equal(values[0], "");
    });
  });
});

// ══════════════════════════════════════════════════════════════════════════
// Gate 6: No new ?raw Gleam imports outside known descriptor files
// ══════════════════════════════════════════════════════════════════════════

describe("Gate: no unregistered Gleam imports in authored modules", () => {
  const modules = findAllAuthoredModules();
  const knownFiles = new Set(
    [...SNIPPET_DESCRIPTOR_FILES, ...LITERAL_GLEAM_ALLOWLIST].map((f) => resolve(websiteRoot, f)),
  );

  for (const absModule of modules) {
    const relModule = relative(websiteRoot, absModule);

    it(`${relModule}: no ?raw Gleam imports outside known descriptor files`, () => {
      if (knownFiles.has(absModule)) return; // known file, checked by other gates
      const source = readFileSync(absModule, "utf-8");
      const rawImports = extractRawImportPaths(source, dirname(absModule));
      const gleamImports = rawImports.filter((p) => p.endsWith(".gleam"));

      assert.equal(
        gleamImports.length,
        0,
        `${relModule} has Gleam ?raw imports [${gleamImports.join(", ")}] but is not in SNIPPET_DESCRIPTOR_FILES — add it or use a registry`,
      );
    });
  }

  describe("negative — catches a new data module with raw Gleam import", () => {
    it("detects ?raw .gleam import in unknown module", () => {
      const fake = `import counterSource from "../../../examples/clap_counter/src/main.gleam?raw";\n`;
      const rawImports = extractRawImportPaths(fake, websiteRoot);
      const gleamImports = rawImports.filter((p) => p.endsWith(".gleam"));
      assert.ok(gleamImports.length > 0, "should detect raw Gleam import");
    });
  });
});

// ══════════════════════════════════════════════════════════════════════════
// Gate 7: ?raw import paths and paths objects agree
// ══════════════════════════════════════════════════════════════════════════

describe("Gate: registry imports match paths objects", () => {
  for (const file of ["src/data/practice-snippets.ts", "src/data/standalone-snippets.ts"]) {
    it(`${file}: every paths value has a matching ?raw import`, () => {
      const absPath = resolve(websiteRoot, file);
      const source = readFileSync(absPath, "utf-8");
      const pathValues = new Set(extractPathsObjectValues(source));
      const rawImports = new Set(extractRawImportPaths(source, dirname(absPath)));

      for (const p of pathValues) {
        assert.ok(
          rawImports.has(p),
          `${file}: paths object has "${p}" but no matching ?raw import`,
        );
      }
    });
  }
});
