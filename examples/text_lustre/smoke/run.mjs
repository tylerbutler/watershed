// Runs the Gleam text smoke test (bundled to dist/smoke.mjs) under Node by
// supplying a WebSocket global for the Phoenix JS client.
import WS from "ws";
globalThis.WebSocket = WS;

const mod = await import("../dist/smoke.mjs");
mod.main();
