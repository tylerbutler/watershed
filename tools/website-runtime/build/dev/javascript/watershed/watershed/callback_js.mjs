/// <reference types="./callback_js.d.mts" />
import { Ok, Error } from "../gleam.mjs";
import { capture as capture_ffi, report } from "./callback_ffi.mjs";

export { report };

/**
 * Invoke application code and return its exception as an error.
 */
export function capture(work) {
  return capture_ffi(
    work,
    (var0) => { return new Ok(var0); },
    (var0) => { return new Error(var0); },
  );
}
