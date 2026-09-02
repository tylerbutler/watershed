// ──────────────────────────────────────────────────────────────────────────
// Snippet model and extractor.
// Guide sheets quote the checked-in examples rather than retyping them.
// A snippet cannot drift from the source it claims to show.
// `?raw` imports provide the whole file. These functions pull one unit of
// code out of it and fail the build when that unit is gone or invalid.
// ──────────────────────────────────────────────────────────────────────────

/** One unit of code shown to the reader. */
export interface Snippet {
  /** The extracted code text. */
  code: string;
  /** Language identifier for syntax highlighting. */
  language: string;
  /** Source file path. Used for citation and drift detection. */
  sourcePath: string;
  /** URL to the canonical source of this snippet, e.g. a GitHub permalink. */
  sourceUrl?: string;
  /** How the code was selected from the source. */
  origin: SnippetOrigin;
}

export type SnippetOrigin =
  | { kind: "definition"; heads: string[] }
  | { kind: "marker"; name: string }
  | { kind: "file" }
  | { kind: "literal" }
  | { kind: "composite"; parts: SnippetOrigin[] };

const MARKER_START = /^\s*\/\/\s*docs:snippet-start\s+(\S+)\s*$/;
const MARKER_END = /^\s*\/\/\s*docs:snippet-end\s+(\S+)\s*$/;

/**
 * Extract one or more top-level definitions from source, in the order given.
 * Comments directly above each definition are included.
 * Multiple definitions are separated by a blank line.
 */
export function snippetFromDefinition(
  source: string,
  sourcePath: string,
  language: string,
  ...heads: string[]
): Snippet {
  if (heads.length === 0) {
    throw new Error("snippetFromDefinition: no heads provided");
  }
  const lines = source.split("\n");
  const code = heads
    .map((head) => extractDefinition(lines, head, sourcePath))
    .join("\n\n");
  return { code, language, sourcePath, origin: { kind: "definition", heads } };
}

/**
 * Extract a named marker range from source.
 * Removes the marker lines. Normalizes indentation of the extracted range.
 */
export function snippetFromMarker(
  source: string,
  sourcePath: string,
  language: string,
  name: string,
): Snippet {
  const code = extractMarkerRange(source, name, sourcePath);
  return { code, language, sourcePath, origin: { kind: "marker", name } };
}

/**
 * Wrap an existing code string as a Snippet without extracting from source.
 * Use for full-file imports or manually curated code strings that are not
 * extracted with snippetFromDefinition or snippetFromMarker.
 */
export function snippetFromLiteral(
  code: string,
  language: string,
  sourcePath: string,
  sourceUrl?: string,
): Snippet {
  return { code, language, sourcePath, sourceUrl, origin: { kind: "literal" } };
}

/**
 * A whole source file as one snippet, without its marker directive lines.
 *
 * A sheet that shows a complete module cannot use a marker range: the Gleam
 * formatter moves a directive written above a `////` module doc comment
 * below it, which would drop the header from the listing. Other sheets still
 * quote parts of the same module by marker, so the directives are dropped
 * here rather than shown to the reader.
 *
 * The Gleam generator's `wholeFile` selector produces the same string for the
 * same file, byte for byte: directive lines removed, one blank line kept at
 * each seam, every other byte and the final newline untouched.
 */
export function snippetFromWholeFile(
  source: string,
  sourcePath: string,
  language: string,
): Snippet {
  return {
    code: withoutMarkerDirectives(source),
    language,
    sourcePath,
    origin: { kind: "file" },
  };
}

/**
 * The source text with snippet marker directives removed.
 *
 * The formatter puts a blank line on each side of a directive line that
 * stands between two items. Dropping the directive line alone would leave
 * two blank lines, so one of the two goes with it.
 */
function withoutMarkerDirectives(source: string): string {
  const lines = source.split("\n");
  const kept: string[] = [];
  let previousIsBlank = false;
  for (let i = 0; i < lines.length; i += 1) {
    if (isMarkerDirective(lines[i])) {
      if (previousIsBlank && lines[i + 1]?.trim() === "") i += 1;
      continue;
    }
    kept.push(lines[i]);
    previousIsBlank = lines[i].trim() === "";
  }
  return kept.join("\n");
}

/**
 * Join two extractions from the same file into one snippet.
 *
 * The result's origin is a composite that keeps *both* parts, in order.
 * An earlier version kept only the first part's origin, which made a
 * two-marker snippet claim single-marker provenance — a gate reading
 * `origin` then vouched for half the code it was shown. Nothing may
 * describe a joined snippet by one of its halves.
 */
export function combineSnippets(
  first: Snippet,
  second: Snippet,
  sourcePath: string,
  separator = "\n\n",
): Snippet {
  return {
    code: first.code + separator + second.code,
    language: first.language,
    sourcePath,
    origin: { kind: "composite", parts: [first.origin, second.origin] },
  };
}

/**
 * Every non-composite origin reachable from `origin`, in order.
 * A composite contributes its parts, recursively; every other kind
 * contributes itself. Use this rather than `origin.kind` when asking
 * whether a snippet is source-backed.
 */
export function originParts(origin: SnippetOrigin): SnippetOrigin[] {
  if (origin.kind !== "composite") return [origin];
  return origin.parts.flatMap(originParts);
}

/** True when no part of this snippet's origin is a hand-written literal. */
export function isSourceBacked(snippet: Snippet): boolean {
  return originParts(snippet.origin).every((o) => o.kind !== "literal");
}

// ── Definition extraction ──────────────────────────────────────────────────

function isMarkerDirective(line: string): boolean {
  return MARKER_START.test(line) || MARKER_END.test(line);
}

function extractDefinition(
  lines: string[],
  head: string,
  sourcePath: string,
): string {
  const loc = sourcePath || "(source)";
  const start = lines.findIndex((line) => line.startsWith(head));
  if (start === -1) {
    throw new Error(
      `snippet: no top-level line starts with "${head}" in ${loc}`,
    );
  }

  // Include the comment block directly above the definition. A marker
  // directive is punctuation for the generator, not part of the definition,
  // so the walk stops at one instead of quoting it back to the reader.
  let from = start;
  while (
    from > 0 &&
    /^\s*\/\//.test(lines[from - 1]) &&
    !isMarkerDirective(lines[from - 1])
  ) {
    from -= 1;
  }

  let depth = 0;
  let opened = false;
  for (let i = start; i < lines.length; i += 1) {
    for (const char of lines[i]) {
      if (char === "{") {
        depth += 1;
        opened = true;
      } else if (char === "}") {
        depth -= 1;
      }
    }
    if (opened && depth === 0) return lines.slice(from, i + 1).join("\n");
    // A definition with no braces ends at the next blank line.
    if (!opened && lines[i].trim() === "") {
      return lines.slice(from, i).join("\n");
    }
  }

  throw new Error(`snippet: "${head}" is never closed in ${loc}`);
}

// ── Marker extraction ──────────────────────────────────────────────────────
// Markers use the form: // docs:snippet-start <name> / // docs:snippet-end <name>

function extractMarkerRange(
  source: string,
  name: string,
  sourcePath: string,
): string {
  const loc = sourcePath || "(source)";
  const lines = source.split("\n");

  const starts: Array<{ index: number; name: string }> = [];
  const ends: Array<{ index: number; name: string }> = [];

  for (let i = 0; i < lines.length; i += 1) {
    const sm = MARKER_START.exec(lines[i]);
    const em = MARKER_END.exec(lines[i]);
    if (sm) starts.push({ index: i, name: sm[1] });
    if (em) ends.push({ index: i, name: em[1] });
  }

  const matchStarts = starts.filter((s) => s.name === name);
  if (matchStarts.length === 0) {
    throw new Error(`snippet: no start marker for "${name}" in ${loc}`);
  }
  if (matchStarts.length > 1) {
    throw new Error(`snippet: duplicate start marker for "${name}" in ${loc}`);
  }

  const matchEnds = ends.filter((e) => e.name === name);
  if (matchEnds.length === 0) {
    throw new Error(`snippet: no end marker for "${name}" in ${loc}`);
  }
  if (matchEnds.length > 1) {
    throw new Error(`snippet: duplicate end marker for "${name}" in ${loc}`);
  }

  const start = matchStarts[0];
  const end = matchEnds[0];

  if (end.index <= start.index) {
    throw new Error(
      `snippet: end marker for "${name}" comes before start in ${loc}`,
    );
  }

  for (const s of starts) {
    if (s.name !== name && s.index > start.index && s.index < end.index) {
      throw new Error(
        `snippet: nested start marker "${s.name}" inside "${name}" in ${loc}`,
      );
    }
  }

  for (const e of ends) {
    if (e.name !== name && e.index > start.index && e.index < end.index) {
      throw new Error(
        `snippet: mismatched end marker "${e.name}" inside "${name}" in ${loc}`,
      );
    }
  }

  const rangeLines = lines.slice(start.index + 1, end.index);

  if (rangeLines.every((l) => l.trim() === "")) {
    throw new Error(`snippet: empty range for "${name}" in ${loc}`);
  }

  return dedent(rangeLines);
}

function dedent(lines: string[]): string {
  const nonEmpty = lines.filter((l) => l.trim() !== "");
  const minIndent = Math.min(
    ...nonEmpty.map((l) => l.match(/^( *)/)?.[1].length ?? 0),
  );
  return lines
    .map((l) => (l.trim() === "" ? "" : l.slice(minIndent)))
    .join("\n")
    .replace(/[\n\s]+$/, "");
}
