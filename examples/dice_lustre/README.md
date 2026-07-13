# watershed dice — Gleam-end-to-end collaborative dice roller

A [Lustre](https://lustre.build) single-page app whose **entire client is
Gleam** compiled to JavaScript: UI, optimistic `SharedMap`, wire codecs, and the
reconnect state machine. The only non-Gleam pieces are a thin FFI shim over the
official [Phoenix JS client](https://www.npmjs.com/package/phoenix) and Lustre's
own runtime.

It reuses the *same* pure core as the BEAM client (`watershed/map_kernel`,
`watershed/wire`, `watershed/runtime_core`) — only the transport + runtime
differ per target:

| Layer | BEAM (`watershed`) | Browser (`watershed_js`) |
| --- | --- | --- |
| Transport | aquamarine (gun / roost) | phoenix.js via FFI |
| Runtime | `runtime` (OTP actor) | `runtime_js` (callbacks + mutable cell) |
| Pure core | `map_kernel` · `wire` · `runtime_core` (shared, unchanged) | ← same |

## Run it

Start a levee dev server in the `levee` repo:

```sh
just server   # registers tenant "dev-tenant" in dev mode, listens on :4000
```

Then, in this directory:

```sh
pnpm install          # phoenix + esbuild
pnpm run build        # gleam build --target javascript, then esbuild bundle
pnpm run serve        # serves index.html on http://localhost:8080
```

From the watershed repo root, the install/build portion is available as:

```sh
just deps
just build
```

Open **two** browser tabs on <http://localhost:8080>. Roll in one; the other
updates. Hit **Force reconnect** and keep rolling — nothing is lost or
duplicated. Each tab is a distinct client (random user id).

## Debugging divergence

Each tab includes a **Diagnostics** panel and writes the same trace to the
browser console. When two tabs disagree, preserve both console logs and compare:

- `phase`: a tab stuck in `reconnecting` or `catching-up` has not reconciled.
- `sn`: both quiescent tabs should reach the same last-seen sequence number.
- `in_flight`: local edits still awaiting their sequenced acknowledgement.
- `buffered`: out-of-order ops waiting for a missing sequence number.
- `resubmit_at`: the reconnect checkpoint that must be reached before pending
  edits are restamped and resubmitted.
- `client`: changes after reconnect; use it with local/remote map event lines to
  identify which connection authored an operation.

In DevTools, enable **Preserve log**, reproduce the problem, then capture the
WebSocket frames alongside the console output. A useful failure report includes
both tabs' diagnostic logs, the first sequence number where `sn` differs, and
whether either tab has nonzero `in_flight` or `buffered`.

> The demo mints an HS256 dev JWT in the browser using levee's dev secret. This
> is for local dev only; a real deployment issues tokens from a backend and
> never ships the tenant secret to the client.

## Headless smoke test

`src/smoke.gleam` drives two clients from Node against a running `just server`,
asserting convergence and reconnect safety (concurrent edits, a same-key LWW
race, a forced mid-session reconnect with edits applied during the drop):

```sh
pnpm install
gleam build --target javascript
pnpm exec esbuild build/dev/javascript/dice_lustre/smoke.mjs \
  --bundle --format=esm --outfile=dist/smoke.mjs
node smoke/run.mjs   # supplies a WebSocket global for phoenix.js
# → SMOKE PASS: clients converged across a reconnect
```

## Status

This is the **M5 spike** proving a Gleam-end-to-end Lustre client is feasible by
reusing the pure core. Productizing it (splitting the pure core into its own
package so a JS app doesn't build the erlang runtime, a Lustre-native reconnect
UX, presence) is follow-on work.
