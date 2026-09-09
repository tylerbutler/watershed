/** @typedef {"function"|"method"|"class"|"type"|"constant"} SymbolKind */
/** @typedef {{line:number, column:number, byte:number}} Position */
/** @typedef {{start:Position, end:Position}} Range */
/** @typedef {{path:string, message:string, range:Range|null}} Diagnostic */
/** @typedef {{reason:string, range:Range}} SkippedRegion */
/** @typedef {{id:string, name:string, qualifiedName:string, container:string[],
 * kind:SymbolKind, visibility:string, exported:boolean, signature:string,
 * range:Range, target:string|null}} SymbolEntry */
/** @typedef {{symbols:SymbolEntry[], diagnostics:Diagnostic[], skippedRegions:SkippedRegion[]}} ParseResult */

export const kinds = ["function", "method", "class", "type", "constant"];
export const statuses = ["indexed", "unsupported", "excluded", "parse-error", "unreadable"];
export const extensions = [".gleam", ".js", ".mjs", ".cjs", ".jsx", ".ts", ".mts", ".cts", ".tsx", ".astro"];
export const limits = [
  "Syntax only; no inferred types, references, call graph, or runtime-generated methods.",
  "Named declarations and callable bindings; not unbound anonymous callbacks.",
  "Gleam constructors are represented by their enclosing type.",
  "Astro frontmatter and executable scripts only; no template expressions, styles, event attributes, or external script contents.",
  "Other formats are inventoried but not parsed.",
];

export function compare(a, b) { return a < b ? -1 : a > b ? 1 : 0; }

export { positionAtUtf16, positionAtByte, rangeAt } from "../src/code_map_ffi.mjs";
import { source_span } from "../src/code_map_ffi.mjs";

export function rawSymbol(source, declaration) {
  const { name, container = [], kind, start, end, signatureEnd = end,
    visibility = "local", exported = false, target = null } = declaration;
  const [signature, from, to] = source_span(source, start, end, signatureEnd);
  return {
    name, container, kind, visibility, exported, signature, target,
    range: { start: { line: from[0], column: from[1], byte: from[2] },
      end: { line: to[0], column: to[1], byte: to[2] } },
  };
}
