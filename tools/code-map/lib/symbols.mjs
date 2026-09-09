/** @typedef {"function"|"method"|"class"|"type"|"constant"} SymbolKind */
/** @typedef {{line:number, column:number, byte:number}} Position */
/** @typedef {{start:Position, end:Position}} Range */
/** @typedef {{path:string, message:string, range:Range|null}} Diagnostic */
/** @typedef {{reason:string, range:Range}} SkippedRegion */
/** @typedef {{id:string, name:string, qualifiedName:string, container:string[],
 * kind:SymbolKind, visibility:string, exported:boolean, signature:string,
 * range:Range, target:string|null}} SymbolEntry */
/** @typedef {{symbols:SymbolEntry[], diagnostics:Diagnostic[], skippedRegions:SkippedRegion[]}} ParseResult */

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
