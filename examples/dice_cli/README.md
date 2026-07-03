# watershed dice CLI — Erlang-target dice roller

An Erlang-target counterpart to [`dice_lustre`](../dice_lustre) that joins the
*same* levee session, proving the pure watershed core drives both runtimes over
one shared document.

## Architecture

| Layer | dice_cli (Erlang) | dice_lustre (JS) |
| --- | --- | --- |
| Transport | aquamarine (gun/roost) | phoenix.js via FFI |
| Runtime | `runtime` (OTP actor) | `runtime_js` (callbacks) |
| Token | `watershed.dev_token` | `watershed_js.dev_token` |
| Pure core | `map_kernel` · `wire` · `runtime_core` (shared) | ← same |

## Prerequisites

Start a levee dev server from the `levee` repo:

```sh
just server   # registers tenant "dev-tenant", listens on :4000
```

## Run it

```sh
cd examples/dice_cli
gleam run
```

The CLI:

1. Mints a dev JWT via `watershed.dev_token`.
2. Connects to `127.0.0.1:4000` (IPv4 literal — see note below).
3. Subscribes to the root map's event `Subject`.
4. Prints the current document state.
5. Rolls `int.random(6) + 1` every 5 seconds, writing through
   `watershed.delete` + `watershed.set`.
6. Prints every local or remote event by looping on `process.receive` through a
   selector, then re-reads optimistic state with `get` and `entries`.
7. Keeps running until you press Ctrl+C.

## Cross-runtime smoke test (manual)

1. Open `dice_lustre` in a browser tab (`pnpm run serve` from
   `examples/dice_lustre`).
2. Run `gleam run` from this directory and leave it running.
3. Roll in the browser — the CLI should print the remote event and refreshed
   entries.
4. Wait for the CLI's periodic roll — the browser tab should update its die
   display to the CLI's roll.

Both clients share `tenant = "dev-tenant"` and `document = "dice"`, so all
edits converge through the same levee document.

## IPv4 literal

This example uses `host = "127.0.0.1"`, **not** `"localhost"`. Erlang's default
`inet6fb4` resolver stalls ~8 s on the AAAA lookup for `"localhost"` before
falling back to IPv4 — long enough for levee to drop the socket as idle.

## Build check

```sh
gleam build --target erlang   # from this directory
```

Or from the repo root:

```sh
gleam build --target erlang   # builds the watershed library itself
```
