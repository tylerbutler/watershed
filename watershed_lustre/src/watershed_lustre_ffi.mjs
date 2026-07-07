// The two schedulers every watershed_lustre effect is built on.
//
// `queue_microtask` defers a dispatch to the end of the current task so a
// callback watershed fires synchronously (possibly from inside a running Lustre
// `update`) never clobbers the dispatch of the update it interrupted.
// `set_timeout` backs the `after` timer effect.

export function queue_microtask(action) {
  queueMicrotask(action);
  return undefined;
}

export function set_timeout(action, ms) {
  setTimeout(action, ms);
  return undefined;
}
