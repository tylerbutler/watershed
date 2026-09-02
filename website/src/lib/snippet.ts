// ──────────────────────────────────────────────────────────────────────────
// Snippet model and manifest loader.
//
// Sheets quote the checked-in examples rather than retyping them, so a
// snippet cannot drift from the source it claims to show. The extraction
// itself is not done here: `tools/source-snippets` reads the marker ranges
// declared in `website/snippets.json` and writes `src/generated/snippets.json`,
// which is generated, ignored, and rebuilt before every build and test run.
//
// This module decodes that manifest, refuses anything malformed, and hands
// out one snippet per id. A missing id or a bad entry fails the build here
// rather than putting unchecked code in front of a reader.
// ──────────────────────────────────────────────────────────────────────────
import generatedManifest from "../generated/snippets.json" with { type: "json" };

/** One unit of code shown to the reader. */
export interface Snippet {
  /** The code text, exactly as the generator selected it. */
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

/**
 * Where a snippet's code comes from.
 *
 * `source` and `file` are both generated: one names the marker ranges it
 * composed, the other is a complete module with its directive lines removed.
 * `literal` is hand-written illustrative code that has no compiled source.
 *
 * The marker list is `readonly` because the decoder freezes it: every page
 * that asks for an id gets the same array, so an edit would be an edit for
 * all of them.
 */
export type SnippetOrigin =
  | { kind: "source"; markers: readonly string[] }
  | { kind: "file" }
  | { kind: "literal" };

/** The manifest schema this loader understands. */
const MANIFEST_VERSION = 1;

/**
 * Decode a generated manifest into one snippet per id.
 *
 * The argument is `unknown` on purpose: the manifest is a build artefact
 * from another program, so nothing about its shape is assumed. Every
 * departure from the schema throws, naming the entry at fault. There is no
 * fallback, because a silently empty manifest would take every code block
 * off the site without failing the build.
 */
export function decodeManifest(value: unknown): Map<string, Snippet> {
  const document = asRecord(value, "manifest");

  if (document.version !== MANIFEST_VERSION) {
    throw new Error(
      `snippet manifest: version ${JSON.stringify(document.version)} is not the supported version ${MANIFEST_VERSION}`,
    );
  }

  const entries = asRecord(document.snippets, "snippets");
  const snippets = new Map<string, Snippet>();
  for (const id of Object.keys(entries).sort()) {
    snippets.set(id, decodeEntry(id, entries[id]));
  }
  return snippets;
}

const snippets = decodeManifest(generatedManifest);

/**
 * The generated snippet with this id.
 *
 * The id is the one declared in `website/snippets.json`. An id nothing
 * generates is a typo or a stale reference, and either way the reader would
 * get a blank where code belongs, so it throws.
 */
export function sourceSnippet(id: string): Snippet {
  const snippet = snippets.get(id);
  if (snippet === undefined) {
    throw new Error(
      `snippet: no generated snippet with id "${id}" — website/snippets.json declares the ids, and the manifest is generated from it`,
    );
  }
  return snippet;
}

/** Every generated id, sorted, for tests and inventory checks. */
export function sourceSnippetIds(): string[] {
  return [...snippets.keys()];
}

/**
 * Hand-written code as a Snippet.
 *
 * Use it for illustrative code with no compiled source: a comparison with
 * another library, a shell command, a directory listing. Everything that
 * quotes real source comes from the manifest instead.
 */
export function snippetFromLiteral(
  code: string,
  language: string,
  sourcePath: string,
  sourceUrl?: string,
): Snippet {
  requireText(code, "code", "literal snippet");
  requireText(language, "language", "literal snippet");
  requireText(sourcePath, "sourcePath", "literal snippet");
  return { code, language, sourcePath, sourceUrl, origin: { kind: "literal" } };
}

/**
 * The same snippet with a link on its source path.
 *
 * A source URL is frontend policy — where this repository happens to be
 * published — so it is added here rather than generated. Everything the
 * manifest decided is copied through untouched, and the snippet passed in is
 * left alone.
 */
export function withSourceUrl(snippet: Snippet, sourceUrl: string): Snippet {
  requireText(sourceUrl, "sourceUrl", "source link");
  return { ...snippet, sourceUrl };
}

/** True when this snippet is generated from real source, not hand-written. */
export function isSourceBacked(snippet: Snippet): boolean {
  return snippet.origin.kind !== "literal";
}

// ── Decoding ──────────────────────────────────────────────────────────────

function decodeEntry(id: string, value: unknown): Snippet {
  const entry = asRecord(value, `entry "${id}"`);
  return Object.freeze({
    code: decodeField(id, entry.code, "code"),
    language: decodeField(id, entry.language, "language"),
    sourcePath: decodeField(id, entry.sourcePath, "sourcePath"),
    origin: decodeOrigin(id, entry.origin),
  });
}

function decodeField(id: string, value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(
      `snippet manifest: entry "${id}" has no usable ${field} (${JSON.stringify(value)})`,
    );
  }
  return value;
}

function decodeOrigin(id: string, value: unknown): SnippetOrigin {
  const origin = asRecord(value, `entry "${id}" origin`);

  if (origin.kind === "file") {
    if ("markers" in origin) {
      throw new Error(
        `snippet manifest: entry "${id}" is a whole-file listing, so it must name no markers`,
      );
    }
    return Object.freeze({ kind: "file" as const });
  }

  if (origin.kind !== "source") {
    throw new Error(
      `snippet manifest: entry "${id}" has origin kind ${JSON.stringify(origin.kind)}, which is neither "source" nor "file"`,
    );
  }

  const markers = origin.markers;
  if (!Array.isArray(markers) || markers.length === 0) {
    throw new Error(
      `snippet manifest: entry "${id}" selects marker ranges but names no markers`,
    );
  }
  for (const marker of markers) {
    if (typeof marker !== "string" || marker.trim() === "") {
      throw new Error(
        `snippet manifest: entry "${id}" has an empty marker id in its markers list`,
      );
    }
  }
  return Object.freeze({
    kind: "source" as const,
    markers: Object.freeze([...markers]),
  });
}

function asRecord(value: unknown, what: string): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error(
      `snippet manifest: ${what} is ${JSON.stringify(value) ?? "undefined"}, not an object`,
    );
  }
  return value as Record<string, unknown>;
}

function requireText(value: string, field: string, what: string): void {
  if (value.trim() === "") {
    throw new Error(`snippet: ${what} needs a ${field}`);
  }
}
