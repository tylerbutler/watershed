// The demo's own URL reading. Kept here rather than in the library: which
// query parameters an application uses to configure signaling and ICE is the
// application's business, and watershed deliberately has no opinion about it.

export function queryParam(name, fallback) {
  const href = globalThis.location?.href;
  if (!href) return fallback;
  const value = new URL(href).searchParams.get(name);
  return value === null || value === "" ? fallback : value;
}

// Signaling failures arrive on a socket callback, outside Lustre's dispatch
// loop. The app hands us a sink once, on the effect that owns `dispatch`.
let signalingSink = () => {};

export function setSignalingSink(sink) {
  signalingSink = sink;
}

export function reportSignalingFailure(detail) {
  signalingSink(detail);
}

// Without this, the IndexedDB snapshot the app calls "disk-first" is evictable
// under storage pressure. Resolves false wherever the API is absent (node, old
// browsers) rather than throwing.
export function requestPersistentStorage() {
  const storage = globalThis.navigator?.storage;
  if (typeof storage?.persist !== "function") return Promise.resolve(false);
  return storage.persist().then(
    (granted) => granted === true,
    () => false,
  );
}
