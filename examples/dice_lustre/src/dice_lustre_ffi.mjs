// Browser-side helpers for the dice app.
export function queue_microtask(action) {
  queueMicrotask(action);
  return undefined;
}
