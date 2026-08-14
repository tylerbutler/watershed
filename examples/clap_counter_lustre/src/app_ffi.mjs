// The demo's own URL reading. Kept here rather than in the library: which
// query parameters an application uses to configure signaling and ICE is the
// application's business, and watershed deliberately has no opinion about it.

export function queryParam(name, fallback) {
  const value = new URL(globalThis.location.href).searchParams.get(name);
  return value === null || value === "" ? fallback : value;
}
