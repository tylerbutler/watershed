// Browser-side helpers for the JavaScript facade (`watershed_js`).
//
// The declarative `ensure_*` bootstrap waits for sync and retries handle
// resolution on a timer rather than blocking (the BEAM facade blocks instead).

export function set_timeout(action, ms) {
  setTimeout(action, ms);
  return undefined;
}
