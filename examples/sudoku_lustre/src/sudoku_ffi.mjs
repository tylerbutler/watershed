// Browser-side helpers for the Sudoku app.
export function queue_microtask(action) {
  queueMicrotask(action);
  return undefined;
}

export function set_timeout(action, ms) {
  setTimeout(action, ms);
  return undefined;
}

export function now_ms() {
  return Date.now();
}
