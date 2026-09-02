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
