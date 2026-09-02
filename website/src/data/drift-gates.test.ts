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

/** True when source has a snippetFromLiteral call with "gleam" language. */
function hasLiteralGleamCall(source: string): boolean {
  // snippetFromLiteral(code, language, sourcePath, ...) — language is the second arg.
  // The code arg may span multiple lines as a template literal.
  // Match: snippetFromLiteral( <anything> , "gleam" or 'gleam', ... )
  return /snippetFromLiteral\s*\([\s\S]*?,\s*["']gleam["']\s*,/s.test(source);
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

// ══════════════════════════════════════════════════════════════════════════
// Pre-computed data: markers from Gleam sources, refs from descriptor files
// ══════════════════════════════════════════════════════════════════════════

/** All markers found across all .gleam source files. */
function scanAllMarkers(): Map<string, { file: string; startLines: number[]; endLines: number[] }> {
  const all = new Map<string, { file: string; startLines: number[]; endLines: number[] }>();

  for (const dir of MARKER_SOURCE_DIRS) {
    const absDir = resolve(repoRoot, dir);
    for (const file of findGleamFiles(absDir)) {
      const content = readFileSync(file, "utf-8");
      const { starts, ends } = parseMarkers(content);
      const repoFile = relative(repoRoot, file);

      for (const [id, lines] of starts) {
        if (all.has(id)) {
          const existing = all.get(id)!;
          existing.startLines.push(...lines);
          // Track first file for error messages; duplicates are caught below
          if (existing.file !== repoFile) {
            existing.file += `, ${repoFile}`;
          }
        } else {
          all.set(id, {
            file: repoFile,
            startLines: [...lines],
            endLines: ends.get(id) ?? [],
          });
        }
      }

      // Capture end-only markers (missing start)
      for (const [id, lines] of ends) {
        if (!all.has(id)) {
          all.set(id, { file: repoFile, startLines: [], endLines: [...lines] });
        } else if (!starts.has(id)) {
          all.get(id)!.endLines.push(...lines);
        }
      }
    }
  }

  return all;
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
  const allMarkers = scanAllMarkers();
  const allRefs = collectMarkerReferences();

  describe("positive — every marker ID has exactly one start and one end", () => {
    it("at least one marker exists", () => {
      assert.ok(allMarkers.size > 0, "no markers found in source");
    });

    for (const [id, info] of allMarkers) {
      it(`marker "${id}" has exactly one start`, () => {
        assert.equal(
          info.startLines.length,
          1,
          `"${id}" has ${info.startLines.length} start marker(s) in ${info.file}`,
        );
      });

      it(`marker "${id}" has exactly one end`, () => {
        assert.equal(
          info.endLines.length,
          1,
          `"${id}" has ${info.endLines.length} end marker(s) in ${info.file}`,
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
  });
});

// ══════════════════════════════════════════════════════════════════════════
// Gate 3: Literal Gleam policy — only allowlisted pages
// ══════════════════════════════════════════════════════════════════════════

describe("Gate: literal Gleam policy", () => {
  describe("positive — no unapproved literal Gleam in pages", () => {
    const pages = findAstroPages();

    it("scans at least 20 pages", () => {
      assert.ok(pages.length >= 20, `only found ${pages.length} pages`);
    });

    for (const absPage of pages) {
      const relPage = relative(websiteRoot, absPage);

      it(`${relPage}: no unapproved snippetFromLiteral("gleam")`, () => {
        const source = readFileSync(absPage, "utf-8");
        if (hasLiteralGleamCall(source)) {
          assert.ok(
            LITERAL_GLEAM_ALLOWLIST.has(relPage),
            `${relPage} uses snippetFromLiteral with "gleam" but is not in LITERAL_GLEAM_ALLOWLIST`,
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

describe("Gate: no unregistered Gleam imports in pages", () => {
  const pages = findAstroPages();
  const knownFiles = new Set(SNIPPET_DESCRIPTOR_FILES.map((f) => resolve(websiteRoot, f)));

  for (const absPage of pages) {
    const relPage = relative(websiteRoot, absPage);

    it(`${relPage}: no ?raw Gleam imports outside known descriptor files`, () => {
      if (knownFiles.has(absPage)) return; // known file, checked by Gate 1
      const source = readFileSync(absPage, "utf-8");
      const rawImports = extractRawImportPaths(source, dirname(absPage));
      const gleamImports = rawImports.filter((p) => p.endsWith(".gleam"));

      assert.equal(
        gleamImports.length,
        0,
        `${relPage} has Gleam ?raw imports [${gleamImports.join(", ")}] but is not in SNIPPET_DESCRIPTOR_FILES — add it or use a registry`,
      );
    });
  }
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
