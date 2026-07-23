// Grapheme utilities for the SharedText demo.
//
// SharedText indexes by grapheme — a user-perceived character — never by UTF-16
// code unit. A `textarea`, however, only reports its value as a UTF-16 string
// and a caret as a code-unit offset. This module bridges that gap: it segments
// a string into graphemes and diffs two revisions into one minimal grapheme
// edit, so a keystroke becomes a single `text_insert` / `text_delete_range` /
// `text_replace_range` against CRDT grapheme indexes — never a raw UTF-16
// offset, which would split a family emoji or strand a combining mark.

// `Intl.Segmenter` is Baseline (widely available since 2024) and gives true
// grapheme clusters: 👨‍👩‍👧 (a ZWJ sequence) and é (e + combining acute) each
// count as one. The code-point fallback below is only reached on older engines
// that predate `Intl.Segmenter`; it splits on whole code points via the string
// iterator, so it still never bisects a surrogate pair (it can, on those old
// engines only, over-split a ZWJ emoji or combining mark — but it never emits
// invalid UTF-16, so every index it yields is a safe CRDT edit boundary).
const segmenter: Intl.Segmenter | null =
  typeof Intl !== "undefined" && "Segmenter" in Intl
    ? new Intl.Segmenter(undefined, { granularity: "grapheme" })
    : null;

/** Split a string into its grapheme clusters. */
export function segmentGraphemes(str: string): string[] {
  if (str === "") return [];
  if (segmenter) {
    const out: string[] = [];
    for (const { segment } of segmenter.segment(str)) out.push(segment);
    return out;
  }
  // Fallback: whole code points (surrogate-pair safe), older engines only.
  return Array.from(str);
}

/** Grapheme count of a string. */
export function graphemeLength(str: string): number {
  if (str === "") return 0;
  if (segmenter) {
    let n = 0;
    for (const _ of segmenter.segment(str)) n++;
    return n;
  }
  return Array.from(str).length;
}

/**
 * One minimal grapheme edit turning `oldStr` into `newStr`, found by trimming
 * the longest common grapheme prefix and suffix. `start`/`end` are grapheme
 * indexes into `oldStr` (an `[start, end)` half-open range); `insert` is the
 * replacement string. Returns `null` when the strings are already equal.
 *
 *   • pure insertion  → `start === end`, `insert !== ""`
 *   • pure deletion   → `start < end`,  `insert === ""`
 *   • replacement     → `start < end`,  `insert !== ""`
 */
export interface GraphemeEdit {
  start: number;
  end: number;
  insert: string;
}

export function minimalGraphemeEdit(
  oldStr: string,
  newStr: string,
): GraphemeEdit | null {
  if (oldStr === newStr) return null;
  const oldG = segmentGraphemes(oldStr);
  const newG = segmentGraphemes(newStr);
  const oldLen = oldG.length;
  const newLen = newG.length;

  // Longest common prefix (in graphemes).
  let prefix = 0;
  const maxPrefix = Math.min(oldLen, newLen);
  while (prefix < maxPrefix && oldG[prefix] === newG[prefix]) prefix++;

  // Longest common suffix, not overlapping the prefix on either side.
  let suffix = 0;
  const maxSuffix = Math.min(oldLen, newLen) - prefix;
  while (
    suffix < maxSuffix &&
    oldG[oldLen - 1 - suffix] === newG[newLen - 1 - suffix]
  ) {
    suffix++;
  }

  const start = prefix;
  const end = oldLen - suffix;
  const insert = newG.slice(prefix, newLen - suffix).join("");
  return { start, end, insert };
}

// ── caret bridging (UTF-16 offset ⇆ grapheme index) ─────────────────────────
// A `textarea` caret is a UTF-16 code-unit offset; a SharedText index is a
// grapheme count. These convert between them so a caret survives a remote
// reflow, and so anchors/edits are pinned at grapheme boundaries — never a raw
// UTF-16 offset that could split a cluster.

/** Grapheme index of the caret at UTF-16 `offset` within `value`. */
export function utf16ToGrapheme(value: string, offset: number): number {
  if (offset <= 0) return 0;
  let units = 0;
  let index = 0;
  for (const g of segmentGraphemes(value)) {
    if (units >= offset) break;
    units += g.length;
    index += 1;
  }
  return index;
}

/** UTF-16 offset at the start of grapheme `index` within `value`. */
export function graphemeToUtf16(value: string, index: number): number {
  if (index <= 0) return 0;
  let units = 0;
  let seen = 0;
  for (const g of segmentGraphemes(value)) {
    if (seen >= index) break;
    units += g.length;
    seen += 1;
  }
  return units;
}

/** Grapheme index of the first occurrence of `needle`, or `null` if absent. */
export function findGraphemeIndex(value: string, needle: string): number | null {
  const at = value.indexOf(needle);
  if (at < 0) return null;
  return utf16ToGrapheme(value, at);
}
