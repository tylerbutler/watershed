// Node-side helpers for the live JS integration suite. None of these exist as
// browser globals the Gleam side can reach, and `sleep` is a promise rather
// than a callback so the suite can `await` it like any other step.
export function sleep(ms) {
  return new Promise((resolve) => setTimeout(() => resolve(undefined), ms));
}

export function log(message) {
  console.log(message);
  return undefined;
}

export function exit(code) {
  process.exit(code);
  return undefined;
}
