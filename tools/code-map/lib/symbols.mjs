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

export function positionAtUtf16(source, offset) {
  if (!Number.isInteger(offset) || offset < 0 || offset > source.length) {
    throw new Error(`Invalid source offset: ${offset}`);
  }
  if (offset > 0 && offset < source.length
      && /[\uD800-\uDBFF]/.test(source[offset - 1]) && /[\uDC00-\uDFFF]/.test(source[offset])) {
    throw new Error("Offset is not on a Unicode boundary");
  }
  const prefix = source.slice(0, offset);
  const lines = prefix.split("\n");
  return { line: lines.length, column: [...lines.at(-1)].length + 1, byte: Buffer.byteLength(prefix) };
}

export function positionAtByte(source, byte) {
  const bytes = Buffer.from(source);
  if (!Number.isInteger(byte) || byte < 0 || byte > bytes.length) throw new Error(`Invalid byte offset: ${byte}`);
  if (byte < bytes.length && (bytes[byte] & 0xc0) === 0x80) throw new Error("Offset is not on a Unicode boundary");
  return positionAtUtf16(source, bytes.subarray(0, byte).toString().length);
}

export function rangeAt(source, start, end) {
  if (end < start) throw new Error("Reversed source range");
  return { start: positionAtUtf16(source, start), end: positionAtUtf16(source, end) };
}

export function makeSymbol(path, source, declaration) {
  const { name, container = [], kind, start, end, signatureEnd = end,
    visibility = "local", exported = false, target = null } = declaration;
  if (typeof name !== "string" || !name || !kinds.includes(kind)
      || !container.every((part) => typeof part === "string") || signatureEnd < start || signatureEnd > end) {
    throw new Error(`Invalid parser declaration for ${path}`);
  }
  const range = rangeAt(source, start, end);
  return {
    id: JSON.stringify([path, container, name, range.start.byte, range.end.byte]),
    name, qualifiedName: `${path}::${[...container, name].join(".")}`,
    container, kind, visibility, exported,
    signature: source.slice(start, signatureEnd).trimEnd(), range, target,
  };
}

export function sortSymbols(symbols) {
  return symbols.sort((a, b) => a.range.start.byte - b.range.start.byte
    || compare(a.kind, b.kind) || compare(a.name, b.name));
}
