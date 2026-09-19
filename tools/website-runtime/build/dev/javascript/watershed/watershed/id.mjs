/// <reference types="./id.d.mts" />
import { uuidV4 as do_uuid_v4 } from "./id_ffi.mjs";

/**
 * Generate a random RFC 4122 UUID v4. The result is lowercase and
 * hyphenated.
 */
export function uuid_v4() {
  return do_uuid_v4();
}
