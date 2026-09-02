// ──────────────────────────────────────────────────────────────────────────
// Copy gates — dependency-free checks that catch volatile prose patterns,
// banlisted phrases, and factual drift in authored website copy.
//
// Each gate targets a specific category of copy regression. The checks
// operate on raw file content, scoped to authored prose by stripping
// frontmatter, style blocks, script blocks, and code comments before
// matching. False positives in code samples and legitimate literal uses
// are avoided by pattern design, not broad exclusions.
//
// Run: node --strip-types --test src/data/copy-gates.test.ts
// ──────────────────────────────────────────────────────────────────────────
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { resolve, dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const websiteRoot = resolve(__dirname, "../..");
const pagesDir = resolve(websiteRoot, "src/pages");
const componentsDir = resolve(websiteRoot, "src/components");
const dataDir = resolve(websiteRoot, "src/data");

// ══════════════════════════════════════════════════════════════════════════
// Helpers
// ══════════════════════════════════════════════════════════════════════════

/** Collect files matching a pattern under a directory, recursively. */
function collectFiles(dir: string, ext: string): string[] {
  const results: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) results.push(...collectFiles(full, ext));
    else if (entry.name.endsWith(ext) && !entry.name.includes(".test.")) results.push(full);
  }
  return results;
}

/**
 * Everything that is not authored body copy: frontmatter (which holds the
 * code samples and every import), style and script blocks, and comments of
 * all three kinds. What is left is what the page renders.
 */
function stripNonProse(content: string): string {
  // Remove frontmatter (--- ... ---)
  const fmMatch = content.match(/^---\n[\s\S]*?\n---\n/);
  let prose = fmMatch ? content.slice(fmMatch[0].length) : content;

  // Remove <style> blocks
  prose = prose.replace(/<style[\s\S]*?<\/style>/gi, "");
  // Remove <script> blocks
  prose = prose.replace(/<script[\s\S]*?<\/script>/gi, "");
  // Remove HTML comments
  prose = prose.replace(/<!--[\s\S]*?-->/g, "");
  // Remove CSS comments (in case of inline styles)
  prose = prose.replace(/\/\*[\s\S]*?\*\//g, "");
  // Remove JS single-line comments (lines starting with //)
  prose = prose.replace(/^\s*\/\/.*$/gm, "");

  return prose;
}

/**
 * Prose for the banlist gate: inline <code> is dropped as well.
 *
 * A banlisted word inside <code> is an API name, not a stylistic choice —
 * `seam` in `fn seam(` is the function's name, and renaming Gleam to suit a
 * prose banlist is not a copy fix. Mechanics stay out of scope here.
 */
function extractProse(content: string): string {
  // Remove content inside <code> tags (inline code references are not prose)
  return stripNonProse(content).replace(/<code>[\s\S]*?<\/code>/gi, "");
}

/**
 * Prose for the volatile-count gate: inline <code> keeps its text.
 *
 * A number inside <code> is on the page like any other word. The regression
 * this gate exists to stop was written `<code>10 passed, no failures</code>`,
 * so a gate that strips <code> could never have caught it — the rule read
 * green while matching nothing. Counts are copy wherever they are typeset.
 */
function extractVisibleProse(content: string): string {
  return stripNonProse(content).replace(
    /<code>([\s\S]*?)<\/code>/gi,
    (_, inner) => inner,
  );
}

/**
 * Strip non-prose regions from a TypeScript data file so banlist checks
 * match only string literals in rule:/body:/detail:/description: fields,
 * not code comments or variable names.
 */
function extractTsProseStrings(content: string): string {
  // Extract string values from prose-carrying fields in TS data files.
  // Match: rule: "...", body: "...", detail: "...", description: "..."
  // Also match array elements inside how:[], useCases:[], etc.
  const strings: string[] = [];
  const fieldPattern = /(?:rule|body|detail|description|blurb|title)\s*:\s*"([^"]+)"/g;
  let match;
  while ((match = fieldPattern.exec(content)) !== null) {
    strings.push(match[1]);
  }
  // Also extract strings from array values
  const arrayPattern = /(?:how|useCases|body)\s*:\s*\[([\s\S]*?)\]/g;
  while ((match = arrayPattern.exec(content)) !== null) {
    const inner = match[1];
    const strPattern = /"([^"]+)"/g;
    let strMatch;
    while ((strMatch = strPattern.exec(inner)) !== null) {
      strings.push(strMatch[1]);
    }
  }
  return strings.join("\n");
}

// Gather authored page, component, and data files
const astroPages = collectFiles(pagesDir, ".astro");
const astroComponents = collectFiles(componentsDir, ".astro");
const dataFiles = collectFiles(dataDir, ".ts");
const allAstroFiles = [...astroPages, ...astroComponents];

// ══════════════════════════════════════════════════════════════════════════
// Gate 1: No stale volatile counts
// ══════════════════════════════════════════════════════════════════════════

describe("Gate: no stale volatile counts", () => {
  // These exact phrases were replaced with durable wording. If they
  // reappear, the volatile count has been reintroduced.
  const stalePatterns: Array<{ pattern: RegExp; label: string }> = [
    {
      pattern: /1[,.]?392\s+test\s+functions/i,
      label: "stale test count '1,392 test functions'",
    },
    {
      pattern: /105\s+test\s+files/i,
      label: "stale test file count '105 test files'",
    },
    {
      pattern: /\bFourteen\s+complete\s+Lustre\b/i,
      label: "hardcoded 'Fourteen complete Lustre' (should be generated from data)",
    },
    {
      pattern: /\bfourteen\s+complete\s+browser\b/i,
      label: "hardcoded 'fourteen complete browser' (should use durable wording)",
    },
    {
      pattern: /\b10\s+passed,\s+no\s+failures\b/,
      label: "hardcoded '10 passed, no failures' (should use durable wording)",
    },
  ];

  for (const file of allAstroFiles) {
    const rel = relative(websiteRoot, file);
    const content = readFileSync(file, "utf-8");
    const prose = extractVisibleProse(content);

    for (const { pattern, label } of stalePatterns) {
      it(`${rel}: no ${label}`, () => {
        const match = prose.match(pattern);
        assert.equal(
          match,
          null,
          `Found volatile count in ${rel}: "${match?.[0]}"`,
        );
      });
    }
  }

  // ── The rule that was dead ───────────────────────────────────────────────
  // guide/testing.astro read "get <code>10 passed, no failures</code> in about
  // a second" until a0cdc15. Reinstate that exact sentence and the gate must
  // fire; strip <code> first and it cannot.
  describe("negative — the historical phrasing is caught", () => {
    const HISTORICAL = [
      "---",
      "const x = 1;",
      "---",
      "<div class=\"g-out\">",
      "  <p>",
      "    Run <code>gleam test</code> and get <code>10 passed, no failures</code> in",
      "    about a second.",
      "  </p>",
      "</div>",
    ].join("\n");

    const rule = stalePatterns.find((p) =>
      p.label.includes("10 passed, no failures"),
    )!;

    it("fires on the exact sentence that regressed", () => {
      assert.match(extractVisibleProse(HISTORICAL), rule.pattern);
    });

    it("would not have fired with <code> stripped — why the gate reads visible prose", () => {
      assert.doesNotMatch(extractProse(HISTORICAL), rule.pattern);
    });

    it("still fires when the count is plain prose, outside <code>", () => {
      const plain = "<p>You get 10 passed, no failures in about a second.</p>";
      assert.match(extractVisibleProse(plain), rule.pattern);
    });

    it("keeps ignoring frontmatter, scripts, styles, and comments", () => {
      const hidden = [
        "---",
        "const banner = `10 passed, no failures`;",
        "---",
        "<!-- 105 test files -->",
        "<script>const s = '1,392 test functions';</script>",
        "<style>/* 105 test files */</style>",
        "<p>A clean pass.</p>",
      ].join("\n");
      const visible = extractVisibleProse(hidden);
      for (const { pattern } of stalePatterns) {
        assert.doesNotMatch(visible, pattern);
      }
    });
  });
});

// ══════════════════════════════════════════════════════════════════════════
// Gate 2: No banlisted phrases in authored prose
// ══════════════════════════════════════════════════════════════════════════

describe("Gate: no banlisted phrases in page prose", () => {
  // Each entry: a regex scoped to catch the banlist variant in prose,
  // designed to avoid false positives in code or legitimate literal uses.
  //
  // "carries" is only banned when an argument or fact carries something,
  // not when a data structure or message literally contains data (e.g.,
  // "FieldChange carries the previous value"). We skip "carries" here
  // because automated detection cannot distinguish the two uses.
  const banlist: Array<{ pattern: RegExp; label: string }> = [
    { pattern: /\breach(?:es|ing)?\s+for\b/i, label: "'reach for'" },
    { pattern: /\blives?\s+(?:at|in|on)\b/i, label: "'lives at/in/on'" },
    { pattern: /\bgrows?\s+a\b/i, label: "'grows a'" },
    { pattern: /\bshapes?\s+the\b/i, label: "'shape the'" },
    { pattern: /\bfails?\s+loudly\b/i, label: "'fails loudly'" },
    { pattern: /\bload[- ]?bearing\b/i, label: "'load bearing'" },
    { pattern: /\bpinned\s+by\b/i, label: "'pinned by'" },
    { pattern: /\bseam\b/i, label: "'seam'" },
    { pattern: /\bsharpen(?:s|ed|ing)?\b/i, label: "'sharpen'" },
  ];

  for (const file of astroPages) {
    const rel = relative(websiteRoot, file);
    const content = readFileSync(file, "utf-8");
    const prose = extractProse(content);

    for (const { pattern, label } of banlist) {
      it(`${rel}: no ${label}`, () => {
        const match = prose.match(pattern);
        assert.equal(
          match,
          null,
          `Found banlisted phrase in ${rel}: "${match?.[0]}"`,
        );
      });
    }
  }

  // Also check prose-carrying string fields in data files
  const proseDataFiles = dataFiles.filter(
    (f) =>
      f.endsWith("practices.ts") ||
      f.endsWith("structures.ts") ||
      f.endsWith("guide.ts"),
  );
  for (const file of proseDataFiles) {
    const rel = relative(websiteRoot, file);
    const content = readFileSync(file, "utf-8");
    const prose = extractTsProseStrings(content);

    for (const { pattern, label } of banlist) {
      it(`${rel}: no ${label} in data strings`, () => {
        const match = prose.match(pattern);
        assert.equal(
          match,
          null,
          `Found banlisted phrase in ${rel}: "${match?.[0]}"`,
        );
      });
    }
  }
});

// ══════════════════════════════════════════════════════════════════════════
// Gate 3: Examples count consistency
// ══════════════════════════════════════════════════════════════════════════

describe("Gate: example count is generated, not hardcoded", () => {
  it("examples.astro uses exampleCount variable, not a hardcoded number", () => {
    const content = readFileSync(
      join(pagesDir, "examples.astro"),
      "utf-8",
    );
    // The page should derive its count from the examples import
    assert.ok(
      content.includes("examples.length") || content.includes("exampleCount"),
      "examples.astro should derive its count from the examples data import",
    );
  });

  it("examples.astro description uses a variable, not 'Fourteen'", () => {
    const content = readFileSync(
      join(pagesDir, "examples.astro"),
      "utf-8",
    );
    // The description= attribute should use a template literal with the count
    const descriptionMatch = content.match(/description\s*=\s*"[^"]*Fourteen[^"]*"/i);
    assert.equal(
      descriptionMatch,
      null,
      "examples.astro description should not hardcode 'Fourteen'",
    );
  });
});
