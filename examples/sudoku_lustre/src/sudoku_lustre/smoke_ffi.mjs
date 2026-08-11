// Node-side helpers for the smoke test (browser globals aren't present).
export function delay(ms, cb) {
  setTimeout(cb, ms);
  return undefined;
}
export function log(s) {
  console.log(s);
  return undefined;
}
export function exit(code) {
  process.exit(code);
  return undefined;
}
