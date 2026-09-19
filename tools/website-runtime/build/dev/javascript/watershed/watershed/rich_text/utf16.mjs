/// <reference types="./utf16.d.mts" />
import { Ok, Error } from "../../gleam.mjs";
import { length, valid, boundary, slice as slice_unchecked } from "./utf16_ffi.mjs";

export { boundary, length, valid };

/**
 * Return a UTF-16 slice. This function fails unless both endpoints are
 * scalar boundaries.
 */
export function slice(value, start, size) {
  let end = start + size;
  let $ = ((((start >= 0) && (size >= 0)) && (end <= length(value))) && boundary(
    value,
    start,
  )) && boundary(value, end);
  if ($) {
    return new Ok(slice_unchecked(value, start, size));
  } else {
    return new Error(undefined);
  }
}
