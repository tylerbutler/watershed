// Node-side helpers for the smoke test (browser globals aren't present).
const readiness = new Map();

export function delay(ms, callback) {
  setTimeout(callback, ms);
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
export function reset_readiness() {
  readiness.clear();
  return undefined;
}
export function mark_ready(user) {
  readiness.set(user, { status: "ok", reason: "" });
  return undefined;
}
export function mark_ready_error(user, reason) {
  readiness.set(user, { status: "error", reason });
  return undefined;
}
export function readiness_status(user) {
  return readiness.get(user)?.status ?? "pending";
}
export function readiness_reason(user) {
  return readiness.get(user)?.reason ?? "";
}
