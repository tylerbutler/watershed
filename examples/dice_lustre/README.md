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
npm install          # phoenix + esbuild
npm run build        # gleam build --target javascript, then esbuild bundle
npm run serve        # serves index.html on http://localhost:8080
```

Open **two** browser tabs on <http://localhost:8080>. Roll in one; the other
updates. Hit **Force reconnect** and keep rolling — nothing is lost or
duplicated. Each tab is a distinct client (random user id).

> The demo mints an HS256 dev JWT in the browser using levee's dev secret. This
> is for local dev only; a real deployment issues tokens from a backend and
> never ships the tenant secret to the client.

## Headless smoke test

`src/smoke.gleam` drives two clients from Node against a running `just server`,
asserting convergence and reconnect safety (concurrent edits, a same-key LWW
race, a forced mid-session reconnect with edits applied during the drop):

```sh
npm install
gleam build --target javascript
npx esbuild build/dev/javascript/dice_lustre/smoke.mjs \
  --bundle --format=esm --outfile=dist/smoke.mjs
node smoke/run.mjs   # supplies a WebSocket global for phoenix.js
# → SMOKE PASS: clients converged across a reconnect
```

## Status

This is the **M5 spike** proving a Gleam-end-to-end Lustre client is feasible by
reusing the pure core. Productizing it (splitting the pure core into its own
package so a JS app doesn't build the erlang runtime, a Lustre-native reconnect
UX, presence) is follow-on work.
