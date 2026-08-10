// Entry point for the live JS integration suite (`just integration-run-js`).
//
// Two things have to happen before any watershed code loads. The Phoenix JS
// client reads `globalThis.WebSocket`, which Node does not provide, so `ws` is
// installed as that global first. And the suite is a plain `main` rather than a
// `gleam test` case — see the header of `test/live_js.gleam` for why a
// promise-driven suite cannot be one.
//
// This lives outside `test/` on purpose: Gleam copies every non-`.gleam` file
// under `test/` into the build output, so a runner kept there would be
// duplicated into a directory where its relative import no longer resolves.
//
// The import is the raw Gleam output, not a bundle — Node resolves `phoenix`
// from `transport_ffi.mjs` by walking up to the root `node_modules`, so there
// is nothing to bundle for.
import WS from "ws";
globalThis.WebSocket = WS;

const mod = await import("../build/dev/javascript/watershed/live_js.mjs");
mod.main();
