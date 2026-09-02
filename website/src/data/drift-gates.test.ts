// ──────────────────────────────────────────────────────────────────────────
// Drift gates — dependency-free checks that fail when source-backed
// snippets drift from the compiled source they claim to show.
//
// The code itself is selected by `tools/source-snippets`, which reads
// `website/snippets.json` and writes an ignored manifest. Marker integrity
// (uniqueness, pairing, orphans) is enforced by the Gleam generator. These
// gates police the frontend seams: ids stay declared, no page reaches
// around the loader, and literal Gleam stays allowlisted.
//
// Each gate catches one category of drift. Negative tests prove the gate
// fires for fabricated drift; positive tests prove the codebase is clean.
//
// Generate the manifest first: `just snippets`.
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

/** The generator configuration, website-relative. It names every marker range
 *  the Gleam manifest is built from. */
const SNIPPET_CONFIG = "snippets.json";

/** The generated manifest, website-relative. Ignored by git, rebuilt before
 *  every build and test run, and read by exactly one module. */
const SNIPPET_MANIFEST = "src/generated/snippets.json";

/** The one module allowed to import the generated manifest. Everything else
 *  asks for a snippet by id, so no page can reach past the loader's
 *  validation and render an entry it decoded itself. */
const MANIFEST_READER = "src/lib/snippet.ts";

// ══════════════════════════════════════════════════════════════════════════
// Helpers
// ══════════════════════════════════════════════════════════════════════════

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

/** Extract snippet ids from sourceSnippet("id") calls. */
function extractSourceSnippetIds(source: string): string[] {
  const ids: string[] = [];
  const re = /sourceSnippet\(\s*["']([^"']+)["']\s*\)/g;
  let m;
  while ((m = re.exec(source)) !== null) {
    ids.push(m[1]);
  }
  return ids;
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

/**
 * Files that are explicitly exempt from the scope-wide raw-Gleam and
 * literal-Gleam gates — the snippet library itself, test files, and
 * the drift gates test.
 */
const GATE_EXEMPT_PATTERNS = [
  /\.test\.ts$/,          // test suites
  /drift-gates\.test\./,  // this file
  /\/lib\/snippet\.ts$/,  // the snippet library
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

// ══════════════════════════════════════════════════════════════════════════
// Gate 1: Every rendered id is declared, generated, and cites a real file
//
// The frontend no longer names source files; it names snippet ids. An id the
// configuration does not declare is a snippet nobody generates, and an id
// nothing on the site asks for is a configured range nobody reads. Both are
// drift, in opposite directions, so both fail here.
// ══════════════════════════════════════════════════════════════════════════

/** Snippet id → the authored modules that ask for it. */
function collectRequestedIds(): Map<string, string[]> {
  const requested = new Map<string, string[]>();
  for (const absModule of findAllAuthoredModules()) {
    const relModule = relative(websiteRoot, absModule);
    for (const id of extractSourceSnippetIds(readFileSync(absModule, "utf-8"))) {
      if (!requested.has(id)) requested.set(id, []);
      requested.get(id)!.push(relModule);
    }
  }
  return requested;
}

/** Every entry of the generated manifest, by id. */
function generatedEntries(): Map<string, { sourcePath: string; code: string }> {
  const manifestPath = resolve(websiteRoot, SNIPPET_MANIFEST);
  if (!existsSync(manifestPath)) {
    throw new Error(
      `${SNIPPET_MANIFEST} is missing — generate it with \`just snippets\` before running the gates`,
    );
  }
  const manifest = JSON.parse(readFileSync(manifestPath, "utf-8")) as {
    snippets: Record<string, { sourcePath: string; code: string }>;
  };
  return new Map(Object.entries(manifest.snippets));
}

describe("Gate: every rendered snippet id is declared and generated", () => {
  const requested = collectRequestedIds();
  const configuredIds = new Set(configuredSnippets().map((entry) => entry.id));
  const generated = generatedEntries();

  describe("positive — the site, the configuration, and the manifest agree", () => {
    it("the site asks for snippets by id", () => {
      assert.ok(
        requested.size > 40,
        `only ${requested.size} snippet ids are requested — the scan is not finding the pages`,
      );
    });

    for (const [id, users] of requested) {
      it(`"${id}" is declared in ${SNIPPET_CONFIG}`, () => {
        assert.ok(
          configuredIds.has(id),
          `${users.join(", ")} asks for "${id}", which ${SNIPPET_CONFIG} does not declare`,
        );
      });

      it(`"${id}" is in the generated manifest and cites a real file`, () => {
        const entry = generated.get(id);
        assert.ok(entry, `"${id}" is not in ${SNIPPET_MANIFEST}`);
        assert.ok(entry.code.trim().length > 0, `"${id}" generated empty code`);
        assert.ok(
          existsSync(resolve(repoRoot, entry.sourcePath)),
          `"${id}" cites "${entry.sourcePath}", which does not exist at repo root`,
        );
      });
    }

    it("no configured snippet goes unquoted", () => {
      const unread = [...configuredIds].filter((id) => !requested.has(id)).sort();
      assert.deepEqual(
        unread,
        [],
        `these ids are configured and generated but nothing on the site renders them:\n${unread.join("\n")}`,
      );
    });
  });

  describe("negative — catches an id nothing generates", () => {
    it("an invented id is not declared", () => {
      assert.ok(!configuredIds.has("guide-connect-invented"));
      assert.ok(!generated.has("guide-connect-invented"));
    });

    it("finds the ids a module requests", () => {
      const fake = `const a = sourceSnippet("guide-connect-main");\nconst b = sourceSnippet("practice-ffi-surface");`;
      assert.deepEqual(extractSourceSnippetIds(fake), [
        "guide-connect-main",
        "practice-ffi-surface",
      ]);
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
// Gate 4: Source-backed registries — every entry is a generated id
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

  it("practice-snippets.ts names one generated id per practice", () => {
    const source = readFileSync(
      resolve(websiteRoot, "src/data/practice-snippets.ts"),
      "utf-8",
    );
    assert.equal(
      extractSourceSnippetIds(source).length,
      17,
      "every practice reads its code from the manifest",
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

  it("standalone-snippets.ts reads its Gleam from the manifest", () => {
    const source = readFileSync(
      resolve(websiteRoot, "src/data/standalone-snippets.ts"),
      "utf-8",
    );
    assert.ok(
      extractSourceSnippetIds(source).length >= 10,
      "the homepage, runtime, and SharedTree Gleam all come from generated ids",
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
// Gate 5: Only the loader reads the generated manifest
//
// The loader validates every entry before anything renders it. A module that
// imports the generated JSON for itself skips that check, and its snippet
// would be whatever the file happened to hold.
// ══════════════════════════════════════════════════════════════════════════

/** True when the module imports the generated manifest. */
function importsGeneratedManifest(source: string): boolean {
  return /["'][^"']*generated\/snippets\.json["']/.test(source);
}

describe("Gate: only the snippet loader reads the generated manifest", () => {
  const modules = findAllAuthoredModules();

  describe("positive — no authored module imports the manifest", () => {
    for (const absModule of modules) {
      const relModule = relative(websiteRoot, absModule);
      if (relModule === MANIFEST_READER) continue;

      it(`${relModule}: does not import ${SNIPPET_MANIFEST}`, () => {
        assert.ok(
          !importsGeneratedManifest(readFileSync(absModule, "utf-8")),
          `${relModule} imports the generated manifest — ask for a snippet by id so the loader validates it`,
        );
      });
    }
  });

  describe("positive — the loader does read it, and validates it", () => {
    const loader = readFileSync(resolve(websiteRoot, MANIFEST_READER), "utf-8");

    it("the loader imports the generated manifest", () => {
      assert.ok(importsGeneratedManifest(loader));
    });

    it("the loader decodes rather than casts", () => {
      assert.ok(
        loader.includes("decodeManifest"),
        "the manifest must go through a decoder that can reject it",
      );
      assert.ok(
        !/\bas any\b/.test(loader),
        "the loader must not assert the manifest's shape with `as any`",
      );
    });
  });

  describe("negative — catches a module that reads the manifest itself", () => {
    it("detects a generated-manifest import", () => {
      const fake = `import manifest from "../generated/snippets.json" with { type: "json" };`;
      assert.ok(importsGeneratedManifest(fake));
    });

    it("does not flag the checked-in configuration", () => {
      const fake = `const config = JSON.parse(readFileSync("snippets.json", "utf-8"));`;
      assert.ok(!importsGeneratedManifest(fake));
    });
  });
});

// ══════════════════════════════════════════════════════════════════════════
// Gate 6: No ?raw source imports anywhere
//
// Source extraction moved out of the website. A page that reads a .gleam or
// .mjs file with Vite's `?raw` is extracting again, by hand, past every
// check the generator and the loader make.
// ══════════════════════════════════════════════════════════════════════════

describe("Gate: no raw source imports in authored modules", () => {
  const modules = findAllAuthoredModules();

  for (const absModule of modules) {
    const relModule = relative(websiteRoot, absModule);

    it(`${relModule}: no ?raw import of a source file`, () => {
      const source = readFileSync(absModule, "utf-8");
      const rawImports = extractRawImportPaths(source, dirname(absModule));
      const sourceImports = rawImports.filter(
        (p) => p.endsWith(".gleam") || p.endsWith(".mjs"),
      );

      assert.deepEqual(
        sourceImports,
        [],
        `${relModule} reads source with ?raw [${sourceImports.join(", ")}] — ask for a generated snippet by id instead`,
      );
    });
  }

  describe("negative — catches a module that reads source with ?raw", () => {
    it("detects ?raw .gleam import in a module", () => {
      const fake = `import counterSource from "../../../examples/clap_counter/src/main.gleam?raw";\n`;
      const rawImports = extractRawImportPaths(fake, websiteRoot);
      const sourceImports = rawImports.filter((p) => p.endsWith(".gleam"));
      assert.ok(sourceImports.length > 0, "should detect raw Gleam import");
    });

    it("leaves a non-source ?raw import alone", () => {
      const fake = `import gleamToml from "../../../examples/retro_tutorial_lustre/gleam.toml?raw";\n`;
      const rawImports = extractRawImportPaths(fake, websiteRoot);
      const sourceImports = rawImports.filter(
        (p) => p.endsWith(".gleam") || p.endsWith(".mjs"),
      );
      assert.deepEqual(sourceImports, [], "a TOML listing is not extracted source");
    });
  });
});

// ══════════════════════════════════════════════════════════════════════════
// Gate 8: Only SnippetBlock renders Astro's <Code>
//
// The extractor, the registries, and the allowlists above all police the
// *descriptor*. None of them sees a page that imports Astro's `Code`
// component and hands it a string. That is the whole policy bypassed in
// two lines, so it is closed here: one component renders code, and every
// page reaches it through a Snippet.
// ══════════════════════════════════════════════════════════════════════════

/** The one module allowed to import and render Astro's `Code`. */
const CODE_RENDERER = "src/components/SnippetBlock.astro";

/** True when the module imports `Code` from astro:components. */
function importsAstroCode(source: string): boolean {
  const re = /import\s*\{([^}]*)\}\s*from\s*["']astro:components["']/g;
  let m;
  while ((m = re.exec(source)) !== null) {
    const named = m[1].split(",").map((s) => s.trim().split(/\s+as\s+/)[0].trim());
    if (named.includes("Code")) return true;
  }
  return false;
}

/**
 * True when the module renders `<Code ...>`.
 *
 * Case-sensitive and anchored on the tag boundary, so HTML `<code>` and
 * sibling components like `<CodeSample />` do not trip it.
 */
function rendersAstroCode(source: string): boolean {
  return /<Code(?=[\s/>])/.test(source);
}

describe("Gate: only SnippetBlock renders Astro <Code>", () => {
  const modules = findAllAuthoredModules();

  describe("positive — no authored module renders code directly", () => {
    for (const absModule of modules) {
      const relModule = relative(websiteRoot, absModule);
      if (relModule === CODE_RENDERER) continue;

      it(`${relModule}: no direct astro:components Code`, () => {
        const source = readFileSync(absModule, "utf-8");
        assert.ok(
          !importsAstroCode(source),
          `${relModule} imports Code from astro:components — render through SnippetBlock so the snippet carries its source path`,
        );
        assert.ok(
          !rendersAstroCode(source),
          `${relModule} renders <Code> directly — render through SnippetBlock so the snippet carries its source path`,
        );
      });
    }
  });

  describe("positive — SnippetBlock is the renderer, and it takes a Snippet", () => {
    const source = readFileSync(resolve(websiteRoot, CODE_RENDERER), "utf-8");

    it("SnippetBlock imports and renders Code", () => {
      assert.ok(importsAstroCode(source), "SnippetBlock must import Code");
      assert.ok(rendersAstroCode(source), "SnippetBlock must render Code");
    });

    it("SnippetBlock renders only snippet fields, never a bare string", () => {
      assert.match(
        source,
        /<Code\s+code=\{snippet\.code\}\s+lang=\{snippet\.language\}/,
        "SnippetBlock must pass snippet.code and snippet.language, so no caller can substitute a literal",
      );
    });

    it("SnippetBlock displays the snippet's own sourcePath", () => {
      assert.ok(
        source.includes("{snippet.sourcePath}"),
        "SnippetBlock must render snippet.sourcePath — the label is the citation",
      );
    });
  });

  describe("negative — catches the direct-Code bypass", () => {
    it("detects a page that renders <Code> with a Gleam literal", () => {
      const fake = `---
import { Code } from "astro:components";
const code = \`pub fn main() { io.println("hi") }\`;
---
<Code lang="gleam" code={code} />`;
      assert.ok(importsAstroCode(fake), "should detect the Code import");
      assert.ok(rendersAstroCode(fake), "should detect the <Code> element");
    });

    it("detects <Code> even when the import is aliased", () => {
      const fake = `import { Code as Highlight } from "astro:components";`;
      assert.ok(importsAstroCode(fake), "an alias still imports Code");
    });

    it("detects a self-closed <Code/> with no attributes", () => {
      assert.ok(rendersAstroCode(`<Code/>`), "should detect bare <Code/>");
      assert.ok(rendersAstroCode(`<Code>`), "should detect open <Code>");
    });

    it("does not flag HTML <code> inline elements", () => {
      const fake = `<p>Call <code>set_field</code> to write.</p>`;
      assert.ok(!rendersAstroCode(fake), "inline <code> is prose, not a code block");
    });

    it("does not flag sibling components whose name starts with Code", () => {
      const fake = `import CodeSample from "../components/CodeSample.astro";\n<CodeSample />`;
      assert.ok(!rendersAstroCode(fake), "<CodeSample /> is not <Code>");
      assert.ok(!importsAstroCode(fake), "CodeSample is not an astro:components import");
    });

    it("does not flag other astro:components imports", () => {
      const fake = `import { Image } from "astro:components";`;
      assert.ok(!importsAstroCode(fake), "only Code is restricted");
    });
  });
});

// ══════════════════════════════════════════════════════════════════════════
// Gate 9: Snippets are built by the extractor, never by hand
//
// A page can also bypass the policy without touching `Code`: hand-build an
// object with the Snippet shape, hand it to SnippetBlock, and the code is
// on the site with a source path that nothing checked. Only the snippet
// library may construct a Snippet.
// ══════════════════════════════════════════════════════════════════════════

/** Modules allowed to construct a Snippet-shaped object literal. */
const SNIPPET_CONSTRUCTORS = ["src/lib/snippet.ts"];

/**
 * Remove block and line comments.
 *
 * Comments are stripped before any brace scan because they are full of
 * apostrophes and backticks — "the step's sheet", "`:global()`" — and a
 * scanner that treats those as string delimiters swallows the code after
 * them. That is not hypothetical: it is how the first version of this gate
 * missed a rewritten `code:` sitting in plain sight.
 */
function stripComments(source: string): string {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, "");
}

/**
 * Every object literal in the source, as `{ ... }` text.
 *
 * Braces are counted, and only template literals are skipped: after comments
 * are gone, a backtick is a template literal, while an apostrophe is usually
 * just prose. Quotes are therefore *not* treated as delimiters.
 */
function objectLiterals(source: string): string[] {
  const text = stripComments(source);
  const len = text.length;
  const bodies: string[] = [];
  for (let i = 0; i < len; i += 1) {
    const ch = text[i];
    if (ch === "`") { i = skipTemplateLiteral(text, i + 1, len) - 1; continue; }
    if (ch !== "{") continue;

    let depth = 0;
    let j = i;
    for (; j < len; j += 1) {
      const c = text[j];
      if (c === "`") { j = skipTemplateLiteral(text, j + 1, len) - 1; continue; }
      if (c === "{") depth += 1;
      else if (c === "}") {
        depth -= 1;
        if (depth === 0) break;
      }
    }
    bodies.push(text.slice(i, Math.min(j + 1, len)));
  }
  return bodies;
}

/** True when `key` is a property name in this object literal's text. */
function hasKey(body: string, key: string): boolean {
  return new RegExp(`(^|[\\s,{])${key}\\s*:`).test(body);
}

/**
 * True when the source contains an object literal shaped like a Snippet:
 * a `code:` and a `language:` key in the same braces, or an inline
 * `origin: { kind: ... }`. Brace-balanced rather than line-based, so a
 * multi-line literal is caught too.
 */
function hasHandBuiltSnippet(source: string): boolean {
  for (const body of objectLiterals(source)) {
    if (hasKey(body, "code") && hasKey(body, "language")) return true;
    if (/(^|[\s,{])origin\s*:\s*\{\s*kind\s*:/.test(body)) return true;
  }
  return false;
}

/**
 * Provenance fields: what a Snippet claims about where its code came from.
 * `sourceUrl` is not one — it is a link to the same file the sourcePath
 * already names, which is why FieldNotes may add one to a real snippet.
 */
const PROVENANCE_KEYS = ["code", "language", "sourcePath", "origin"];

/**
 * Provenance fields overridden on a cloned snippet, e.g.
 * `{ ...practice.snippet, code: somethingElse }`. Cloning to *add* a
 * sourceUrl is the one legitimate override; rewriting the code or the path
 * it is attributed to is the hand-built descriptor by another route.
 */
function findProvenanceOverrides(source: string): string[] {
  const found: string[] = [];
  for (const body of objectLiterals(source)) {
    // Only the clone-and-override shape: `{ ...x, ... }`.
    if (!/^\{\s*\.\.\./.test(body)) continue;
    for (const key of PROVENANCE_KEYS) {
      if (hasKey(body, key)) found.push(key);
    }
  }
  return found;
}

describe("Gate: snippets are built by the extractor, never by hand", () => {
  const modules = findAllAuthoredModules();

  describe("positive — no authored module hand-builds a Snippet", () => {
    for (const absModule of modules) {
      const relModule = relative(websiteRoot, absModule);
      if (SNIPPET_CONSTRUCTORS.includes(relModule)) continue;

      it(`${relModule}: no hand-built Snippet object`, () => {
        const source = readFileSync(absModule, "utf-8");
        assert.ok(
          !hasHandBuiltSnippet(source),
          `${relModule} builds a Snippet-shaped object by hand — use sourceSnippet, snippetFromLiteral, or withSourceUrl`,
        );
      });
    }
  });

  describe("positive — no authored module rewrites a snippet's provenance", () => {
    for (const absModule of modules) {
      const relModule = relative(websiteRoot, absModule);
      if (SNIPPET_CONSTRUCTORS.includes(relModule)) continue;

      it(`${relModule}: clones a snippet without rewriting its provenance`, () => {
        const source = readFileSync(absModule, "utf-8");
        assert.deepEqual(
          findProvenanceOverrides(source),
          [],
          `${relModule} overrides a provenance field on a cloned snippet — only sourceUrl may be added`,
        );
      });
    }
  });

  describe("negative — catches a hand-built descriptor", () => {
    it("detects code rewritten on a cloned snippet", () => {
      const fake = `const s = { ...practice.snippet, code: "whatever I like" };`;
      assert.deepEqual(findProvenanceOverrides(fake), ["code"]);
    });

    it("detects a sourcePath rewritten on a cloned snippet", () => {
      const fake = `const s = { ...snippet, sourcePath: "examples/not_really.gleam" };`;
      assert.deepEqual(findProvenanceOverrides(fake), ["sourcePath"]);
    });

    it("detects an origin rewritten on a cloned snippet", () => {
      const fake = `const s = { ...snippet, origin: realSnippet.origin };`;
      assert.deepEqual(findProvenanceOverrides(fake), ["origin"]);
    });

    it("allows adding a sourceUrl to a real snippet", () => {
      const fake = `const s = { ...practice.snippet, sourceUrl: practiceSourceUrl(practice) };`;
      assert.deepEqual(findProvenanceOverrides(fake), []);
    });

    it("does not flag an unrelated spread that happens to set code", () => {
      const fake = `const props = { ...rest };\nconst other = { code: 200, status: "ok" };`;
      assert.deepEqual(findProvenanceOverrides(fake), []);
    });


    it("detects an inline Snippet object passed to SnippetBlock", () => {
      const fake = `---
const snippet = {
  code: \`pub fn main() { io.println("hi") }\`,
  language: "gleam",
  sourcePath: "examples/not_really/src/main.gleam",
  origin: { kind: "source", markers: ["invented"] },
};
---
<SnippetBlock snippet={snippet} />`;
      assert.ok(hasHandBuiltSnippet(fake), "should detect the hand-built descriptor");
    });

    it("detects a hand-built descriptor with only code and language", () => {
      const fake = `const s = { code: gleamText, language: "gleam" };`;
      assert.ok(hasHandBuiltSnippet(fake), "code + language is the Snippet shape");
    });

    it("detects a hand-built origin even without a code key", () => {
      const fake = `const o = { ...base, origin: { kind: "source", markers: ["invented"] } };`;
      assert.ok(hasHandBuiltSnippet(fake), "an invented origin is a forged citation");
    });

    it("does not flag an unrelated object with a language key", () => {
      const fake = `const meta = { language: "gleam", title: "Dice CLI" };`;
      assert.ok(!hasHandBuiltSnippet(fake), "language alone is not the Snippet shape");
    });

    it("does not flag prose or a template literal that mentions the keys", () => {
      const fake = "const doc = `a Snippet has { code: string, language: string }`;";
      assert.ok(!hasHandBuiltSnippet(fake), "a template literal is text, not a literal object");
    });

    it("does not flag reading fields off a real snippet", () => {
      const fake = `const { code, language } = snippet;\nconst c = snippet.code;`;
      assert.ok(!hasHandBuiltSnippet(fake), "destructuring is not construction");
    });
  });
});

// ══════════════════════════════════════════════════════════════════════════
// Gate 10: The generator configuration selects one way per snippet
//
// A snippet reads marker ranges or the whole file. Both selectors on one
// entry, or neither, is an ambiguous descriptor, and an ambiguous descriptor
// is a snippet nobody can predict from reading the configuration. The Gleam
// decoder rejects those shapes; this gate keeps the checked-in configuration
// honest without waiting for a Gleam run.
// ══════════════════════════════════════════════════════════════════════════

interface ConfiguredSnippet {
  id: string;
  sourcePath: string;
  language: string;
  markers?: string[];
  wholeFile?: boolean;
  separator?: string;
}

function configuredSnippets(): ConfiguredSnippet[] {
  const config = JSON.parse(
    readFileSync(resolve(websiteRoot, SNIPPET_CONFIG), "utf-8"),
  ) as { snippets: ConfiguredSnippet[] };
  return config.snippets;
}

describe("Gate: configured snippets select markers or a whole file", () => {
  const snippets = configuredSnippets();

  it("the configuration declares snippets", () => {
    assert.ok(snippets.length > 0, `${SNIPPET_CONFIG} declares no snippets`);
  });

  for (const snippet of snippets) {
    it(`${snippet.id}: exactly one selector`, () => {
      const hasMarkers = snippet.markers !== undefined;
      const hasWholeFile = snippet.wholeFile !== undefined;

      assert.ok(
        hasMarkers !== hasWholeFile,
        `${snippet.id} declares ${hasMarkers && hasWholeFile ? "both markers and wholeFile" : "neither markers nor wholeFile"} — a snippet selects one way or the other`,
      );

      if (hasWholeFile) {
        assert.equal(
          snippet.wholeFile,
          true,
          `${snippet.id}: wholeFile takes only true — drop the field instead`,
        );
        assert.equal(
          snippet.separator,
          undefined,
          `${snippet.id}: a whole-file listing joins nothing, so it has no separator`,
        );
      } else {
        assert.ok(
          (snippet.markers ?? []).length > 0,
          `${snippet.id}: an empty marker list selects nothing`,
        );
      }
    });

    it(`${snippet.id}: source file exists`, () => {
      assert.ok(
        existsSync(resolve(repoRoot, snippet.sourcePath)),
        `${snippet.id}: sourcePath "${snippet.sourcePath}" does not exist at repo root`,
      );
    });
  }

  describe("negative — catches an ambiguous entry", () => {
    it("both selectors on one entry is ambiguous", () => {
      const fake: ConfiguredSnippet = {
        id: "fake",
        sourcePath: "src/a.gleam",
        language: "gleam",
        markers: ["a"],
        wholeFile: true,
      };
      assert.ok(
        (fake.markers !== undefined) === (fake.wholeFile !== undefined),
        "both selectors must be rejected",
      );
    });

    it("neither selector on one entry is ambiguous", () => {
      const fake: ConfiguredSnippet = {
        id: "fake",
        sourcePath: "src/a.gleam",
        language: "gleam",
      };
      assert.ok(
        (fake.markers !== undefined) === (fake.wholeFile !== undefined),
        "an entry with no selector must be rejected",
      );
    });
  });
});
