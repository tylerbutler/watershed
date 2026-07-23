export function length(value) { return value.length; }

export function valid(value) {
  for (let i = 0; i < value.length; i += 1) {
    const unit = value.charCodeAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (i + 1 >= value.length) return false;
      const next = value.charCodeAt(i + 1);
      if (next < 0xdc00 || next > 0xdfff) return false;
      i += 1;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

export function boundary(value, offset) {
  if (offset < 0 || offset > value.length) return false;
  if (offset === 0 || offset === value.length) return true;
  const before = value.charCodeAt(offset - 1);
  const after = value.charCodeAt(offset);
  return !(before >= 0xd800 && before <= 0xdbff && after >= 0xdc00 && after <= 0xdfff);
}

export function slice(value, start, size) { return value.slice(start, start + size); }
