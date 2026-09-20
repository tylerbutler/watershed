// ──────────────────────────────────────────────────────────────────────────
// Drift gates — dependency-free checks that fail when source-backed
// snippets drift from the compiled source they claim to show.
//
// The code itself is selected by `tools/source-snippets`, which reads
// `website/snippets.json` and writes an ignored manifest. Marker integrity
// (uniqueness, pairing, orphans) and configuration shape (selectors,
// separators, source paths) are enforced by the Gleam generator, which runs
// before these gates do. These gates police the frontend seams: ids stay
// declared, no page reaches around the loader, and literal Gleam stays
// allowlisted.
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
import { execFileSync } from "node:child_process";
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

/** The one authored module allowed to import generated Gleam output. */
const GENERATED_RUNTIME_GATEWAY = "src/scripts/demo/generated-runtime.ts";
const AUTHORED_INTEROP_MODULE = "src/scripts/demo/gleam-interop.ts";
const LEGACY_GENERATED_DOCUMENT_MODULE =
  "src/scripts/demo/legacy-generated-document.ts";
// Remove this exception only with the later full atlas façade migration.
const ATLAS_RAW_RUNTIME_EXCEPTION = "src/scripts/demo.ts";

const GENERATED_RUNTIME_RAW_CONSUMERS = new Set([
  "src/scripts/counter-bug.ts",
  "src/scripts/directory-demo.ts",
  "src/scripts/demo/sluice-runtime.ts",
  "src/scripts/demo/sluice-runtime.type-test.ts",
  "src/scripts/demo/legacy-generated-document.ts",
  ATLAS_RAW_RUNTIME_EXCEPTION,
  "src/scripts/demo/boot.test.ts",
  "src/scripts/demo/gleam-values.type-test.ts",
  "src/scripts/demo/website-runtime-contract.test.ts",
  "src/scripts/guide-race-demo.ts",
  "src/scripts/json-ot-demo.ts",
  "src/scripts/rich-text-demo.ts",
  "src/scripts/sequence-demo.ts",
  "src/scripts/sudoku-demo.ts",
  "src/scripts/text-demo.ts",
  "src/scripts/text-element-demo.ts",
]);

const LEGACY_GENERATED_DOCUMENT_CONSUMERS = new Set([
  "src/scripts/directory-demo.ts",
  "src/scripts/guide-race-demo.ts",
  "src/scripts/json-ot-demo.ts",
  "src/scripts/rich-text-demo.ts",
  "src/scripts/sequence-demo.ts",
  "src/scripts/sudoku-demo.ts",
  "src/scripts/text-demo.ts",
]);

const AUTHORED_INTEROP_EXPORTS = new Set([
  "ResultValue",
  "expectOk",
  "isOk",
  "isSome",
  "none",
  "optionValue",
  "resultError",
  "resultValue",
  "some",
]);

const GLEAM_CONTAINER_ESCAPES = new Set([
  "Error",
  "None",
  "Ok",
  "Option$None",
  "Option$None$const",
  "Option$Some",
  "Option$Some$0",
  "Option$isNone",
  "Option$isSome",
  "Result$Error",
  "Result$Error$0",
  "Result$Ok",
  "Result$Ok$0",
  "Result$isError",
  "Result$isOk",
  "Some",
]);

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

function skipTemplateLiteral(
  source: string, start: number, len: number,
  onExpression?: (start: number, end: number) => void,
): number {
  let i = start;
  while (i < len) {
    if (source[i] === "\\") { i += 2; continue; }
    if (source[i] === "`") return i + 1;
    if (source[i] === "$" && i + 1 < len && source[i + 1] === "{") {
      const end = skipBalanced(source, i + 1, len, "{", "}");
      onExpression?.(i + 2, end - 1);
      i = end;
      continue;
    }
    i++;
  }
  return i;
}

function skipComment(source: string, start: number, len: number): number {
  if (source.startsWith("//", start)) {
    const end = source.indexOf("\n", start + 2);
    return end === -1 ? len : Math.min(end, len);
  }
  if (source.startsWith("/*", start)) {
    const end = source.indexOf("*/", start + 2);
    return end === -1 ? len : Math.min(end + 2, len);
  }
  return start;
}

function skipBalanced(
  source: string, start: number, len: number,
  open: string, close: string,
): number {
  let depth = 0;
  let i = start;
  while (i < len) {
    const commentEnd = skipComment(source, i, len);
    if (commentEnd !== i) { i = commentEnd; continue; }
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
  /\.test\.(?:ts|js|mjs)$/, // test suites, which fabricate violations
  /drift-gates\.test\./,    // this file
  /\/lib\/snippet\.ts$/,    // the snippet library
];

/** Extensions the gates read. Astro pages and TypeScript modules render the
 *  site; `.js` and `.mjs` modules ship to the browser and can reach around
 *  the loader in exactly the same ways, so the walk reads them too. */
const AUTHORED_EXTENSIONS = [".astro", ".ts", ".js", ".mjs"];

/** All authored website source modules under src, minus test files and the
 *  snippet library itself. */
function findAllAuthoredModules(
  { includeTests = false }: { includeTests?: boolean } = {},
): string[] {
  const srcDir = resolve(websiteRoot, "src");
  const results: string[] = [];
  function walk(dir: string) {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = join(dir, entry.name);
      if (entry.isDirectory() && entry.name !== "node_modules") {
        walk(full);
      } else if (AUTHORED_EXTENSIONS.some((ext) => entry.name.endsWith(ext))) {
        const rel = relative(websiteRoot, full);
        const exemptPatterns = includeTests
          ? GATE_EXEMPT_PATTERNS.filter((pattern) => !pattern.test("file.test.ts"))
          : GATE_EXEMPT_PATTERNS;
        if (!exemptPatterns.some((pattern) => pattern.test(rel))) {
          results.push(full);
        }
      }
    }
  }
  walk(srcDir);
  return results;
}

function gleamContainerImports(source: string): string[] {
  const found = new Set<string>();
  const commentFree = source.replace(
    /("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`)|(\/\/[^\n]*|\/\*[\s\S]*?\*\/)/g,
    (match, literal: string | undefined) =>
      literal === undefined ? " ".repeat(match.length) : literal,
  );
  const tokens =
    /"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`|\bimport\s+(type\s+)?(?:\{([\s\S]*?)\}|\*\s+as\s+([A-Za-z_$][\w$]*))\s+from\s+["']([^"']+)["']/g;
  let match;
  while ((match = tokens.exec(commentFree)) !== null) {
    const [, typeOnly, namedBindings, namespaceBinding, modulePath] = match;
    if (
      (!namedBindings && !namespaceBinding) ||
      typeOnly ||
      !/(?:\/gleam(?:\/option)?|\/prelude)\.mjs$/.test(modulePath)
    ) {
      continue;
    }
    if (namespaceBinding) {
      found.add(`* as ${namespaceBinding}`);
      continue;
    }
    for (const binding of namedBindings.split(",")) {
      const trimmed = binding.trim();
      if (!trimmed || trimmed.startsWith("type ")) continue;
      const imported = trimmed.split(/\s+as\s+/)[0]?.trim();
      if (imported && GLEAM_CONTAINER_ESCAPES.has(imported)) {
        found.add(imported);
      }
    }
  }

  const exports =
    /"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`|\bexport\s+(type\s+)?(?:\{([\s\S]*?)\}|\*(?:\s+as\s+[A-Za-z_$][\w$]*)?)\s+from\s+["']([^"']+)["']/g;
  while ((match = exports.exec(commentFree)) !== null) {
    const [, typeOnly, namedBindings, modulePath] = match;
    if (
      typeOnly ||
      !modulePath ||
      !/(?:\/gleam(?:\/option)?|\/prelude)\.mjs$/.test(modulePath)
    ) {
      continue;
    }
    if (!namedBindings) {
      found.add("export *");
      continue;
    }
    for (const binding of namedBindings.split(",")) {
      const trimmed = binding.trim();
      if (!trimmed || trimmed.startsWith("type ")) continue;
      const imported = trimmed.split(/\s+as\s+/)[0]?.trim();
      if (imported && GLEAM_CONTAINER_ESCAPES.has(imported)) {
        found.add(imported);
      }
    }
  }

  const dynamicImports =
    /"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`|\bimport\s*\(\s*["']([^"']+)["']\s*\)/g;
  while ((match = dynamicImports.exec(commentFree)) !== null) {
    const modulePath = match[1];
    if (
      modulePath &&
      /(?:\/gleam(?:\/option)?|\/prelude)\.mjs$/.test(modulePath)
    ) {
      found.add("dynamic import");
    }
  }

  return [...found].sort();
}

function legacyGleamBuildImports(source: string): string[] {
  return [...source.matchAll(/\bfrom\s+["']([^"']*build\/dev\/javascript\/[^"']+)["']/g)]
    .map((match) => match[1])
    .filter(
      (path) => !path.includes("tools/website-runtime/build/dev/javascript"),
    );
}

function generatedRuntimeImports(source: string): string[] {
  return [...source.matchAll(
    /\bfrom\s+["']([^"']*tools\/website-runtime\/build\/dev\/javascript\/[^"']+)["']/g,
  )].map((match) => match[1]);
}

function importBindingsFrom(
  source: string,
  importerPath: string,
  modulePath: string,
): string[] {
  const found: string[] = [];
  const targetPath = resolve(modulePath);
  const tokens: { kind: "code" | "string" | "template"; value: string }[] = [];
  const identifier = /[A-Za-z_$][\w$]*/y;
  function scan(start: number, end: number): void {
    let i = start;
    while (i < end) {
      const next = skipComment(source, i, end);
      if (next !== i) { i = next; continue; }
      if (/\s/.test(source[i])) { i++; continue; }
      if (source[i] === '"' || source[i] === "'") {
        const next = skipString(source, i, end);
        tokens.push({ kind: "string", value: source.slice(i + 1, next - 1) });
        i = next;
      } else if (source[i] === "`") {
        let interpolated = false;
        const next = skipTemplateLiteral(source, i + 1, end, (start, end) => {
          interpolated = true;
          tokens.push({ kind: "code", value: "`" });
          scan(start, end);
        });
        tokens.push(interpolated
          ? { kind: "code", value: "`" }
          : { kind: "template", value: source.slice(i + 1, next - 1) });
        i = next;
      } else {
        identifier.lastIndex = i;
        const value = identifier.exec(source)?.[0] ?? source[i];
        tokens.push({ kind: "code", value });
        i += value.length;
      }
    }
  }
  scan(0, source.length);
  const is = (index: number, value: string): boolean =>
    tokens[index]?.kind === "code" && tokens[index].value === value;
  const matchesTarget = (index: number, allowTemplate = false): boolean => {
    const token = tokens[index];
    return token !== undefined &&
      (token.kind === "string" || (allowTemplate && token.kind === "template")) &&
      resolve(dirname(importerPath), token.value) === targetPath;
  };
  for (let i = 0; i < tokens.length; i++) {
    if (!is(i, "import") && !is(i, "export")) continue;
    const declaration = tokens[i].value;
    let j = i + 1;
    if (declaration === "import") {
      if (is(j, "(")) {
        if (matchesTarget(j + 1, true) && (is(j + 2, ")") || is(j + 2, ","))) {
          found.push("dynamic import");
        }
        continue;
      }
      if (matchesTarget(j)) {
        found.push("side-effect import");
        continue;
      }
    }
    const bindings: string[] = [];
    const typeOnly = is(j, "type") && !is(j + 1, "from");
    if (typeOnly) j++;
    if (declaration === "import" && tokens[j]?.kind === "code" &&
        /^[A-Za-z_$]/.test(tokens[j].value)) {
      bindings.push("default");
      j++;
      if (is(j, ",")) j++;
    }
    if (is(j, "{")) {
      j++;
      if (is(j, "}")) bindings.push("side-effect import");
      while (j < tokens.length && !is(j, "}") && !is(j, ";")) {
        if (!typeOnly && is(j, "type") && !is(j + 1, ",") &&
            !is(j + 1, "}") && !is(j + 1, "as")) j++;
        bindings.push(tokens[j].value);
        j++;
        if (is(j, "as")) j += 2;
        if (!is(j, ",")) break;
        j++;
      }
      if (!is(j, "}")) continue;
      j++;
    } else if (is(j, "*")) {
      j++;
      if (is(j, "as")) {
        bindings.push(`* as ${tokens[j + 1]?.value}`);
        j += 2;
      } else {
        bindings.push(`${declaration} *`);
      }
    }
    if (is(j, "from") && matchesTarget(j + 1)) found.push(...bindings);
  }
  return found;
}

function legacyGeneratedDocumentImportViolations(
  source: string,
  importerPath: string,
): string[] {
  const relModule = relative(websiteRoot, importerPath);
  if (LEGACY_GENERATED_DOCUMENT_CONSUMERS.has(relModule)) return [];
  return importBindingsFrom(
    source,
    importerPath,
    resolve(websiteRoot, LEGACY_GENERATED_DOCUMENT_MODULE),
  ).map((binding) => `${relModule} -> ${binding}`);
}

function jsonOtRepresentationAccesses(source: string): string[] {
  return [...source.matchAll(
    /\bjsonOt\.(VNull|VBool|VNumber|VString|VArray|VObject|Key|Index|NInt)\b/g,
  )].map((match) => match[1]);
}

function orMapRepresentationAccesses(source: string): string[] {
  return [...source.matchAll(
    /\borMapKernel\.(RegisterMode|TallyMode|Register|Tally)\b/g,
  )].map((match) => match[1]);
}

describe("Gate: generated Gleam imports stay behind one gateway", () => {
  it("only the generated runtime gateway imports compiled modules", () => {
    const violations = findAllAuthoredModules({ includeTests: true }).flatMap(
      (absModule) => {
        const relModule = relative(websiteRoot, absModule);
        if (relModule === GENERATED_RUNTIME_GATEWAY) return [];
        return generatedRuntimeImports(readFileSync(absModule, "utf-8")).map(
          (path) => `${relModule} -> ${path}`,
        );
      },
    );
    assert.deepEqual(violations, []);
  });
});

describe("Gate: demos keep generated representations behind the Gleam façade", () => {
  it("the JSON-OT demo uses every dedicated façade operation", () => {
    const source = readFileSync(
      resolve(websiteRoot, "src/scripts/json-ot-demo.ts"),
      "utf-8",
    );
    assert.deepEqual(jsonOtRepresentationAccesses(source), []);
    for (const operation of [
      "json_ot_parse",
      "json_ot_stringify",
      "json_ot_key",
      "json_ot_index",
      "json_ot_integer",
    ]) {
      assert.match(source, new RegExp(`\\bwebsiteRuntime\\.${operation}\\b`));
    }
  });

  it("detects direct JSON-OT representation access", () => {
    const fake = `
      const value = new jsonOt.VString("ready");
      const key = new jsonOt.Key("site");
      if (value instanceof jsonOt.VString) return value[0];
    `;
    assert.deepEqual(jsonOtRepresentationAccesses(fake), [
      "VString",
      "Key",
      "VString",
    ]);
  });

  it("the guide race uses every dedicated façade operation", () => {
    const source = readFileSync(
      resolve(websiteRoot, "src/scripts/guide-race-demo.ts"),
      "utf-8",
    );
    assert.deepEqual(orMapRepresentationAccesses(source), []);
    for (const operation of [
      "create_register_or_map",
      "create_tally_or_map",
      "register_entries",
      "tally_entries",
    ]) {
      assert.match(source, new RegExp(`\\bwebsiteRuntime\\.${operation}\\b`));
    }
  });

  it("detects direct OR-map representation access", () => {
    const fake = `
      const notes = new orMapKernel.RegisterMode();
      const votes = new orMapKernel.TallyMode();
      if (value instanceof orMapKernel.Register) return value[0];
      if (value instanceof orMapKernel.Tally) return value[0];
    `;
    assert.deepEqual(orMapRepresentationAccesses(fake), [
      "RegisterMode",
      "TallyMode",
      "Register",
      "Tally",
    ]);
  });
});

describe("Gate: Gleam Result and Option constructors stay behind the typed helper", () => {
  it("the boundary scan includes TypeScript test modules", () => {
    const modules = findAllAuthoredModules({ includeTests: true }).map((path) =>
      relative(websiteRoot, path),
    );
    assert.ok(modules.includes("src/scripts/demo/boot.test.ts"));
  });

  it("no authored module imports container constructors directly", () => {
    for (const absModule of findAllAuthoredModules({ includeTests: true })) {
      const relModule = relative(websiteRoot, absModule);
      if (relModule === GENERATED_RUNTIME_GATEWAY) continue;
      assert.deepEqual(
        gleamContainerImports(readFileSync(absModule, "utf-8")),
        [],
        `${relModule} imports a Gleam container constructor directly`,
      );
    }
  });

  it("detects direct container constructor imports", () => {
    const fake = `
      import { Some } from "../../../build/dev/javascript/gleam_stdlib/gleam/option.mjs";
      import { Option$None$const, Option$Some, Option$isSome } from "../../../build/dev/javascript/gleam_stdlib/gleam/option.mjs";
      import { Ok } from "../../../build/dev/javascript/watershed/gleam.mjs";
      import { Result$isOk } from "../../../build/dev/javascript/prelude.mjs";
      import { Error as GleamError } from "../../../build/dev/javascript/watershed/prelude.mjs";
      import * as gleam from "../../../watershed_lustre/build/dev/javascript/watershed/gleam.mjs";
    `;
    assert.deepEqual(gleamContainerImports(fake), [
      "* as gleam",
      "Error",
      "Ok",
      "Option$None$const",
      "Option$Some",
      "Option$isSome",
      "Result$isOk",
      "Some",
    ]);
  });

  it("detects re-exports and dynamic imports of container runtimes", () => {
    const fake = `
      export { Some } from "../../../build/dev/javascript/gleam_stdlib/gleam/option.mjs";
      export * from "../../../build/dev/javascript/prelude.mjs";
      const gleam = await import("../../../watershed_lustre/build/dev/javascript/watershed/gleam.mjs");
    `;
    assert.deepEqual(gleamContainerImports(fake), [
      "Some",
      "dynamic import",
      "export *",
    ]);
  });

  it("allows type-only container imports", () => {
    const fake = `
      import type { Option$, Result } from "../../../build/dev/javascript/watershed/gleam.mjs";
      import { type Ok } from "../../../build/dev/javascript/watershed/gleam.mjs";
    `;
    assert.deepEqual(gleamContainerImports(fake), []);
  });

  it("ignores import-shaped comments and strings", () => {
    const fake = `
      // import { Ok } from "../../../build/dev/javascript/watershed/gleam.mjs";
      const example = 'import { Some } from "../../../build/dev/javascript/gleam_stdlib/gleam/option.mjs"';
    `;
    assert.deepEqual(gleamContainerImports(fake), []);
  });

  it("detects constructors when comments appear inside imports", () => {
    const fake = `
      import /* runtime */ { Ok } from "../../../build/dev/javascript/watershed/gleam.mjs";
      import { /* runtime */ Some } from "../../../build/dev/javascript/gleam_stdlib/gleam/option.mjs";
    `;
    assert.deepEqual(gleamContainerImports(fake), ["Ok", "Some"]);
  });

  it("allows generated domain constructors", () => {
    const fake = `
      import { Set } from "../../../build/dev/javascript/watershed/watershed/pact_map_kernel.mjs";
    `;
    assert.deepEqual(gleamContainerImports(fake), []);
  });
});

describe("Gate: website scripts use one generated Gleam runtime", () => {
  it("resolves generated-runtime imports relative to each importer", () => {
    const gateway = resolve(websiteRoot, GENERATED_RUNTIME_GATEWAY);
    const directImporter = resolve(websiteRoot, "src/scripts/demo.ts");
    const nestedImporter = resolve(
      websiteRoot,
      "src/scripts/nested/consumer.ts",
    );

    assert.deepEqual(
      importBindingsFrom(
        'import { sluice } from "./demo/generated-runtime.ts";',
        directImporter,
        gateway,
      ),
      ["sluice"],
    );
    assert.deepEqual(
      importBindingsFrom(
        'import { watershed } from "../demo/generated-runtime.ts";',
        nestedImporter,
        gateway,
      ),
      ["watershed"],
    );
  });

  it("rejects legacy root and watershed_lustre build imports", () => {
    const fake = `
      import * as root from "../../../build/dev/javascript/watershed/watershed.mjs";
      import * as lustre from "../../../watershed_lustre/build/dev/javascript/watershed/watershed.mjs";
      import * as current from "../../../tools/website-runtime/build/dev/javascript/watershed/watershed.mjs";
    `;
    assert.deepEqual(legacyGleamBuildImports(fake), [
      "../../../build/dev/javascript/watershed/watershed.mjs",
      "../../../watershed_lustre/build/dev/javascript/watershed/watershed.mjs",
    ]);
  });

  it("has no legacy generated-runtime imports", () => {
    const violations = findAllAuthoredModules({ includeTests: true }).flatMap(
      (absModule) =>
        legacyGleamBuildImports(readFileSync(absModule, "utf-8")).map(
          (path) => `${relative(websiteRoot, absModule)} -> ${path}`,
        ),
    );
    assert.deepEqual(violations, []);
  });

  it("shared demo infrastructure consumes the authored interop contract", () => {
    for (const path of [
      "src/scripts/demo/sluice-transport.ts",
      "src/scripts/demo/sequencer.ts",
      "src/scripts/demo/sluice-rig.ts",
    ]) {
      const source = readFileSync(resolve(websiteRoot, path), "utf-8");
      assert.doesNotMatch(source, /from ["'].\/generated-runtime\.ts["']/);
    }
  });

  it("the shared sluice adapter has no raw-document callback escape", () => {
    const source = readFileSync(
      resolve(websiteRoot, "src/scripts/demo/sluice-runtime.ts"),
      "utf-8",
    );
    assert.doesNotMatch(source, /\bexport function withDocument\b/);
  });

  it("dedicated legacy demos use the named document compatibility module", () => {
    const compatibilityModule = resolve(
      websiteRoot,
      LEGACY_GENERATED_DOCUMENT_MODULE,
    );
    const runtimeModule = resolve(
      websiteRoot,
      "src/scripts/demo/sluice-runtime.ts",
    );
    for (const path of LEGACY_GENERATED_DOCUMENT_CONSUMERS) {
      const absModule = resolve(websiteRoot, path);
      const source = readFileSync(absModule, "utf-8");
      assert.deepEqual(
        importBindingsFrom(source, absModule, compatibilityModule),
        ["withLegacyGeneratedDocument"],
        `${path} does not use the legacy document compatibility module`,
      );
      assert.ok(
        !importBindingsFrom(source, absModule, runtimeModule).includes(
          "withDocument",
        ),
        `${path} still imports withDocument from the shared adapter`,
      );
    }
  });

  it("legacy document compatibility stays limited to dedicated demos", () => {
    const violations = findAllAuthoredModules({ includeTests: true }).flatMap(
      (absModule) =>
        legacyGeneratedDocumentImportViolations(
          readFileSync(absModule, "utf-8"),
          absModule,
        ),
    );
    assert.deepEqual(violations, []);
  });

  it("rejects unauthorized legacy document compatibility imports", () => {
    const importer = resolve(
      websiteRoot,
      "src/scripts/demo/unauthorized-consumer.ts",
    );
    const fake =
      'import { withLegacyGeneratedDocument } from "./legacy-generated-document.ts";';
    assert.deepEqual(
      legacyGeneratedDocumentImportViolations(fake, importer),
      [
        "src/scripts/demo/unauthorized-consumer.ts -> withLegacyGeneratedDocument",
      ],
    );
  });

  const compatibilityReferences = [
    {
      name: "named import",
      source: 'import { withLegacyGeneratedDocument as legacy } from "MODULE";',
      binding: "withLegacyGeneratedDocument",
    },
    {
      name: "default import",
      source: 'import legacy from "MODULE";',
      binding: "default",
    },
    {
      name: "namespace import",
      source: 'import * as legacy from "MODULE";',
      binding: "* as legacy",
    },
    {
      name: "side-effect import",
      source: 'import "MODULE";',
      binding: "side-effect import",
    },
    {
      name: "empty import",
      source: 'import {} from "MODULE";',
      binding: "side-effect import",
    },
    {
      name: "dynamic import",
      source: 'const { withLegacyGeneratedDocument } = await import /* legacy */ (\n "MODULE"\n);',
      binding: "dynamic import",
    },
    {
      name: "static template dynamic import",
      source: 'await import(`MODULE`);',
      binding: "dynamic import",
    },
    {
      name: "quoted import inside a template import argument",
      source: 'await import(`./${(await import("MODULE")).name}.ts`);',
      binding: "dynamic import",
    },
    {
      name: "template import inside a template import argument",
      source: 'await import(`./${(await import(`MODULE`)).name}.ts`);',
      binding: "dynamic import",
    },
    {
      name: "import inside nested template interpolation",
      source: 'const text = `outer ${`inner ${await import("MODULE")}`}`;',
      binding: "dynamic import",
    },
    {
      name: "import after comments and nested braces in interpolation",
      source: 'const text = `${({ name: "}" /* } ` */ }).name + /* } */ (await import("MODULE"))}`;',
      binding: "dynamic import",
    },
    {
      name: "named re-export",
      source: 'export /* legacy */ { withLegacyGeneratedDocument as legacy } from "MODULE";',
      binding: "withLegacyGeneratedDocument",
    },
    {
      name: "star re-export",
      source: "export * from 'MODULE';",
      binding: "export *",
    },
    {
      name: "namespace re-export",
      source: 'export * as legacy from "MODULE";',
      binding: "* as legacy",
    },
  ];
  for (const [path, modulePath] of [
    ["src/scripts/demo/unauthorized-consumer.ts", "./legacy-generated-document.ts"],
    ["src/scripts/nested/consumer.ts", "../demo/legacy-generated-document.ts"],
    ["src/scripts/demo/sluice-transport.ts", "../demo/legacy-generated-document.ts"],
    ["src/scripts/demo/sequencer.ts", "./legacy-generated-document.ts"],
    ["src/scripts/demo/sluice-rig.ts", "./legacy-generated-document.ts"],
  ]) {
    for (const { name, source, binding } of compatibilityReferences) {
      it(`rejects legacy document ${name} in ${path}`, () => {
        assert.deepEqual(
          legacyGeneratedDocumentImportViolations(
            source.replace("MODULE", modulePath),
            resolve(websiteRoot, path),
          ),
          [`${path} -> ${binding}`],
        );
      });
    }
  }

  it("allows compatibility references only from the exact dedicated-demo paths", () => {
    for (const path of LEGACY_GENERATED_DOCUMENT_CONSUMERS) {
      for (const { source, binding } of compatibilityReferences) {
        const fake = source.replace("MODULE", "./demo/legacy-generated-document.ts");
        assert.deepEqual(
          legacyGeneratedDocumentImportViolations(fake, resolve(websiteRoot, path)),
          [],
        );
        const unauthorizedPath = path.replace(/\.ts$/, "-copy.ts");
        assert.deepEqual(
          legacyGeneratedDocumentImportViolations(
            fake,
            resolve(websiteRoot, unauthorizedPath),
          ),
          [`${unauthorizedPath} -> ${binding}`],
        );
      }
    }
  });

  it("ignores compatibility-shaped strings, templates, and comments", () => {
    const fake = `
      // import { withLegacyGeneratedDocument } from "./legacy-generated-document.ts";
      /* export * from "./legacy-generated-document.ts"; */
      const example = 'import { withLegacyGeneratedDocument } from "./legacy-generated-document.ts";';
      const dynamic = "import('./legacy-generated-document.ts')";
      const named = 'export { withLegacyGeneratedDocument } from "./legacy-generated-document.ts";';
      const star = \`export * from "./legacy-generated-document.ts";\`;
    `;
    assert.deepEqual(
      legacyGeneratedDocumentImportViolations(
        fake,
        resolve(websiteRoot, "src/scripts/demo/unauthorized-consumer.ts"),
      ),
      [],
    );
  });

  it("does not extend an empty export into an illustrative re-export string", () => {
    const fake = `export {};
const example =
  'export { withLegacyGeneratedDocument } from "./legacy-generated-document.ts";';`;
    assert.deepEqual(
      legacyGeneratedDocumentImportViolations(
        fake,
        resolve(websiteRoot, "src/scripts/demo/unauthorized-consumer.ts"),
      ),
      [],
    );
  });

  it("bounds named declarations across strings, templates, and comments", () => {
    const fake = `
      const local = 1;
      export { local };
      const example = "export { withLegacyGeneratedDocument } from './legacy-generated-document.ts';";
      export {};
      const template = \`export { withLegacyGeneratedDocument } from "./legacy-generated-document.ts";\`;
      export { /* } from "./legacy-generated-document.ts"; */ local as renamed };
      // export { withLegacyGeneratedDocument } from "./legacy-generated-document.ts";
      export { "} from './legacy-generated-document.ts';" as harmless } from "./other.ts";
    `;
    assert.deepEqual(
      legacyGeneratedDocumentImportViolations(
        fake,
        resolve(websiteRoot, "src/scripts/demo/unauthorized-consumer.ts"),
      ),
      [],
    );
  });

  it("ignores inert template text but scans real imports after it", () => {
    const fake = `
      const example = \`escaped \\ \\\` \\\${import("./legacy-generated-document.ts")}\`;
      const text = \`\${"import('./legacy-generated-document.ts')"}\`;
      const dynamic = import(\`./\${name}/legacy-generated-document.ts\`);
      export {};
      export { /* } */ withLegacyGeneratedDocument as legacy } /* gap */ from "./legacy-generated-document.ts";
    `;
    assert.deepEqual(
      legacyGeneratedDocumentImportViolations(
        fake,
        resolve(websiteRoot, "src/scripts/demo/unauthorized-consumer.ts"),
      ),
      ["src/scripts/demo/unauthorized-consumer.ts -> withLegacyGeneratedDocument"],
    );
  });

  it("does not confuse other modules with the compatibility module", () => {
    for (const { source } of compatibilityReferences) {
      for (const modulePath of [
        "./other/legacy-generated-document.ts",
        "./legacy-generated-document.ts.backup",
        "./sluice-runtime.ts",
      ]) {
        assert.deepEqual(
          legacyGeneratedDocumentImportViolations(
            source.replace("MODULE", modulePath),
            resolve(websiteRoot, "src/scripts/demo/unauthorized-consumer.ts"),
          ),
          [],
        );
      }
    }
  });

  it("raw generated exports stay confined to the gateway and named legacy consumers", () => {
    const violations = findAllAuthoredModules({ includeTests: true }).flatMap(
      (absModule) => {
        const relModule = relative(websiteRoot, absModule);
        if (
          relModule === GENERATED_RUNTIME_GATEWAY ||
          relModule === AUTHORED_INTEROP_MODULE ||
          GENERATED_RUNTIME_RAW_CONSUMERS.has(relModule)
        ) {
          return [];
        }
        return importBindingsFrom(
          readFileSync(absModule, "utf-8"),
          absModule,
          resolve(websiteRoot, GENERATED_RUNTIME_GATEWAY),
        )
          .filter((binding) => !AUTHORED_INTEROP_EXPORTS.has(binding))
          .map((binding) => `${relModule} -> ${binding}`);
      },
    );
    assert.deepEqual(violations, []);
  });

  it("the atlas sequencer delegates sequence numbers to sluice", () => {
    const source = readFileSync(
      resolve(websiteRoot, "src/scripts/demo/sequencer.ts"),
      "utf-8",
    );
    const runtimeImports = importBindingsFrom(
      source,
      resolve(websiteRoot, "src/scripts/demo/sequencer.ts"),
      resolve(websiteRoot, "src/scripts/demo/sluice-runtime.ts"),
    );
    assert.ok(runtimeImports.includes("sequenceNumber"));
    assert.ok(runtimeImports.includes("writeSequenceMarker"));
    assert.ok(runtimeImports.includes("DemoDocument"));
    assert.ok(runtimeImports.includes("DemoServer"));
    assert.doesNotMatch(source, /\bsn\s*\+=\s*1\b/);
  });

  it("the atlas leaves runtime bootstrap records behind the Gleam bridge", () => {
    const source = readFileSync(
      resolve(websiteRoot, "src/scripts/demo.ts"),
      "utf-8",
    );
    assert.doesNotMatch(
      source,
      /spillway\/(?:message|types)\.mjs|signet\/types\.mjs/,
    );
    assert.doesNotMatch(
      source,
      /new runtimeCore\.Summary|new message\.ConnectedMessage|new spillway\./,
    );
    for (const operation of [
      "counter_core",
      "counter_increment",
      "counter_pending",
      "counter_value",
      "deliver_counter",
    ]) {
      assert.match(source, new RegExp(`\\bwebsiteRuntime\\.${operation}\\b`));
    }
  });
});

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
        // The generator checks the configured path when it runs. This checks
        // the manifest on disk, which may be older than the tree: a source
        // deleted after the last generation leaves an entry citing a file
        // that is gone, and the site renders that path as its citation.
        assert.ok(
          existsSync(resolve(repoRoot, entry.sourcePath)),
          `"${id}" cites "${entry.sourcePath}", which does not exist at repo root — regenerate with \`just snippets\``,
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
// The checked-in configuration, read for the id inventory above.
//
// Its shape is not policed here. The Gleam decoder owns every rule about
// selectors, separators, and source paths, and it runs before these gates
// do. A second copy of those rules in TypeScript would drift from the
// decoder and enforce yesterday's schema.
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

// ══════════════════════════════════════════════════════════════════════════
// Gate 10: Browser script modules are inside the gates
//
// The gates above walked `.astro` and `.ts` only. A `.js` or `.mjs` module
// under src/scripts is authored code that ships to the browser, and it can
// import source with `?raw`, hand-build a descriptor, or read the manifest
// exactly like a page can. Left unscanned it is an open door, so the walk
// reads it too. Test modules stay outside on purpose: they fabricate
// violations to prove the gates fire.
// ══════════════════════════════════════════════════════════════════════════

/** Every content policy the gates apply, run over one module's source. */
function policyViolations(source: string): string[] {
  const found: string[] = [];
  if (hasLiteralGleamCall(source)) found.push("literal-gleam");
  if (
    extractRawImportPaths(source, websiteRoot).some(
      (p) => p.endsWith(".gleam") || p.endsWith(".mjs"),
    )
  ) {
    found.push("raw-source-import");
  }
  if (hasHandBuiltSnippet(source)) found.push("hand-built-snippet");
  if (importsGeneratedManifest(source)) found.push("manifest-import");
  if (importsAstroCode(source) || rendersAstroCode(source)) found.push("astro-code");
  return found.sort();
}

/** Files git tracks under the website's src tree, website-relative. */
function trackedWebsiteSources(): string[] {
  return execFileSync("git", ["ls-files", "src"], {
    cwd: websiteRoot,
    encoding: "utf-8",
  })
    .split("\n")
    .filter((line) => line.length > 0);
}

describe("Gate: browser script modules are inside the gates", () => {
  const scanned = findAllAuthoredModules().map((p) => relative(websiteRoot, p));

  describe("positive — the walk reads every authored script module", () => {
    it("the walk reaches .js modules", () => {
      assert.ok(
        scanned.some((p) => p.endsWith(".js")),
        "no .js module is scanned — a browser script can bypass every gate",
      );
    });

    it("the walk reaches .mjs modules", () => {
      assert.ok(
        scanned.some((p) => p.endsWith(".mjs")),
        "no .mjs module is scanned — a browser script can bypass every gate",
      );
    });

    it("the walk misses no tracked script module", () => {
      const tracked = trackedWebsiteSources().filter(
        (p) =>
          (p.endsWith(".js") || p.endsWith(".mjs")) &&
          !/\.test\.(?:ts|js|mjs)$/.test(p),
      );
      assert.ok(tracked.length > 0, "git tracks no script module under src");
      const missed = tracked.filter((p) => !scanned.includes(p)).sort();
      assert.deepEqual(
        missed,
        [],
        `these tracked script modules are never scanned:\n${missed.join("\n")}`,
      );
    });

    it("test modules stay outside the gates", () => {
      const tests = scanned.filter((p) => /\.test\.(?:ts|js|mjs)$/.test(p));
      assert.deepEqual(
        tests,
        [],
        `test modules fabricate violations to prove the gates fire, so they cannot be scanned:\n${tests.join("\n")}`,
      );
    });

    it("no authored script module violates a policy", () => {
      for (const relModule of scanned.filter(
        (p) => p.endsWith(".js") || p.endsWith(".mjs"),
      )) {
        assert.deepEqual(
          policyViolations(readFileSync(resolve(websiteRoot, relModule), "utf-8")),
          [],
          `${relModule} violates a snippet policy`,
        );
      }
    });
  });

  describe("negative — a script module cannot bypass the policies", () => {
    it("catches a raw Gleam import in a script module", () => {
      const fake = `import src from "../../../examples/dice_cli/src/dice_cli.gleam?raw";\n`;
      assert.ok(policyViolations(fake).includes("raw-source-import"));
    });

    it("catches literal Gleam in a script module", () => {
      const fake = `export const s = snippetFromLiteral(\`import gleam/io\`, "gleam", "(illustrative)");`;
      assert.ok(policyViolations(fake).includes("literal-gleam"));
    });

    it("catches a hand-built descriptor in a script module", () => {
      const fake = `export const snippet = {
  code: "pub fn main() { Nil }",
  language: "gleam",
  sourcePath: "examples/dice_cli/src/dice_cli.gleam",
};`;
      assert.ok(policyViolations(fake).includes("hand-built-snippet"));
    });

    it("catches a manifest read in a script module", () => {
      const fake = `import manifest from "../generated/snippets.json" with { type: "json" };`;
      assert.ok(policyViolations(fake).includes("manifest-import"));
    });

    it("catches every bypass at once", () => {
      const fake = `import manifest from "../generated/snippets.json" with { type: "json" };
import src from "../../../examples/dice_cli/src/dice_cli.gleam?raw";
import { Code } from "astro:components";
export const a = snippetFromLiteral(\`import gleam/io\`, "gleam", "(illustrative)");
export const snippet = {
  code: src,
  language: "gleam",
  sourcePath: "examples/dice_cli/src/dice_cli.gleam",
};`;
      assert.deepEqual(policyViolations(fake), [
        "astro-code",
        "hand-built-snippet",
        "literal-gleam",
        "manifest-import",
        "raw-source-import",
      ]);
    });

    it("leaves a clean script module alone", () => {
      const fake = `export function boot() {\n  document.querySelector("#demo")?.classList.add("ready");\n}\n`;
      assert.deepEqual(policyViolations(fake), []);
    });
  });
});
