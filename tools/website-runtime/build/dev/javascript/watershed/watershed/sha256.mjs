/// <reference types="./sha256.d.mts" />
import { hex as do_hex } from "./sha256_ffi.mjs";

/**
 * The SHA-256 of the UTF-8 bytes of a string, as 64 lowercase hex
 * characters.
 */
export function hex(input) {
  return do_hex(input);
}
