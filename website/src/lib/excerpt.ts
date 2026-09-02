// ──────────────────────────────────────────────────────────────────────────
// Compatibility wrapper. Pages still calling excerpt() will continue to
// work while they migrate to snippetFromDefinition() in snippet.ts.
// ──────────────────────────────────────────────────────────────────────────
import { snippetFromDefinition } from "./snippet.ts";

/**
 * Quote one or more top-level definitions from Gleam source, in the order
 * given, separated by a blank line. `heads` are the exact prefixes of the
 * lines the definitions start on, e.g. `"pub fn add_note("`.
 *
 * @deprecated Use snippetFromDefinition() from ./snippet.ts instead.
 */
export function excerpt(source: string, ...heads: string[]): string {
  return snippetFromDefinition(source, "", "gleam", ...heads).code;
}

/**
 * Quote a contiguous run of lines: from the first line starting with `from`,
 * up to but not including the first later line starting with `to`. Use this
 * for the inside of a big `case`, where the unit worth showing is a few
 * branches rather than a whole definition.
 */
export function section(source: string, from: string, to: string): string {
  const lines = source.split("\n");
  const start = lines.findIndex((line) => line.startsWith(from));
  if (start === -1) throw new Error(`section: no line starts with ${from}`);
  const end = lines.findIndex(
    (line, i) => i > start && line.startsWith(to),
  );
  if (end === -1) throw new Error(`section: no line starts with ${to}`);
  return lines
    .slice(start, end)
    .join("\n")
    .replace(/\s+$/, "");
}
