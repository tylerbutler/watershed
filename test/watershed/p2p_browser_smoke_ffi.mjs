// Browser-safe helpers for the WebRTC smoke harness. Deliberately free of
// Node globals: this module is imported by a page running in Chrome.

export function sleep(ms) {
  return new Promise((resolve) => setTimeout(() => resolve(undefined), ms));
}

export function nowMs() {
  return Date.now();
}
