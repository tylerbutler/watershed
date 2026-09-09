export function raise_error(message) {
  throw new Error(message);
}

export function is_undefined(value) {
  return value === undefined;
}

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

export function source_span(source, start, end, signatureEnd) {
  if (signatureEnd < start || signatureEnd > end) throw new Error("Invalid signature range");
  positionAtUtf16(source, signatureEnd);
  const range = rangeAt(source, start, end);
  return [source.slice(start, signatureEnd).trimEnd(),
    [range.start.line, range.start.column, range.start.byte],
    [range.end.line, range.end.column, range.end.byte]];
}
