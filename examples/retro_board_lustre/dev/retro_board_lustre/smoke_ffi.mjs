// Node-only helpers for the smoke test: browser globals are absent, so the
// Gleam side gets a timer, a logger, and an exit code through FFI.
export function delay(ms, callback) {
  setTimeout(callback, ms);
}

export function log(message) {
  console.log(message);
}

export function exit(code) {
  process.exit(code);
}
