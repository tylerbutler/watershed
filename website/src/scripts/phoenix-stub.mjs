// Build-time stub for the optional `phoenix` peer dependency.
//
// watershed's `transport_ffi.mjs` does a guarded `await import("phoenix")` so
// the runtime can load without phoenix when a non-phoenix transport is used.
// The website's demos drive the runtime through the in-memory `sluice`, which
// injects its own transport and never calls the phoenix `connect()`, so phoenix
// is genuinely unused here. This stub lets Vite resolve the import without
// pulling the real package into the bundle; `Socket` stays `undefined`, and
// `transport_ffi.connect` throws a clear error only if it is ever actually used.
export const Socket = undefined;
