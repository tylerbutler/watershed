// ──────────────────────────────────────────────────────────────────────────
// Snippet extraction for the build guide.
// Guide sheets quote the checked-in examples rather than retyping them, so a
// snippet cannot drift from the source it claims to show. `?raw` imports give
// us the whole file; this pulls one top-level Gleam definition out of it by
// its opening line, and fails the build if that line is gone.
// ──────────────────────────────────────────────────────────────────────────

/**
 * Quote one or more top-level definitions from Gleam source, in the order
 * given, separated by a blank line. `heads` are the exact prefixes of the
 * lines the definitions start on, e.g. `"pub fn add_note("`.
 */
export function excerpt(source: string, ...heads: string[]): string {
  const lines = source.split("\n");
  return heads.map((head) => definition(lines, head)).join("\n\n");
}

function definition(lines: string[], head: string): string {
  const start = lines.findIndex((line) => line.startsWith(head));
  if (start === -1) {
    throw new Error(`excerpt: no top-level line starts with ${head}`);
  }

  // Take the doc comment or inline comment sitting directly above it.
  let from = start;
  while (from > 0 && /^\s*\/\//.test(lines[from - 1])) from -= 1;

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
    // A definition with no braces at all ends at the next blank line.
    if (!opened && lines[i].trim() === "") {
      return lines.slice(from, i).join("\n");
    }
  }

  throw new Error(`excerpt: ${head} is never closed`);
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
