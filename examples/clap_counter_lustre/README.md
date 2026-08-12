# watershed clap counter — Medium-style collaborative claps

A [Lustre](https://lustre.build) single-page app with one channel: a
`PnCounter` that never decrements. Open two tabs on the same document and hold
the clap button down in both — the most direct possible stress test of a
counter under concurrency, since the value is a state-based CRDT merge, not a
serialized last-write-wins.

## Why `PnCounter` and not something grow-only

Claps only ever go up, so a dedicated grow-only counter (a G-Counter) would be
the more honest primitive. Watershed doesn't have one: the vendored
`lattice_counters` package ships `g_counter.gleam`, but nothing in
`src/watershed/` wires it up — no kernel, no facade type, no schema
`ChannelField` variant. This example uses `PnCounter` and simply never calls
its decrement path. See `docs/demo-ideas.md` for the note tracking the gap.

`PnCounter` was also, until this example, a facade with no demo: the JS/Lustre
`subscribe_pn_counter` binding shipped in `5cea5d6`, but nothing in
`examples/` exercised it end to end.

## Run it

Start a floodgate dev server from the repository root:

```sh
just integration-up   # seeds tenant "dev-tenant", listens on :4000
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

Open **two** browser tabs on <http://localhost:8080>. Hold the clap button
down in both at once — the count only ever goes up, and both tabs converge on
the same total. Hit **Force reconnect** and keep clapping: nothing is lost or
double-counted.

## Debugging divergence

Each tab includes a **Diagnostics** panel and writes the same trace to the
browser console — same fields as the dice example (`phase`, `sn`, `in_flight`,
`buffered`, `resubmit_at`, `client`). See `examples/dice_lustre/README.md` for
what each one means.

> The demo mints an HS256 dev JWT in the browser using the server's dev secret.
> This is for local dev only; a real deployment issues tokens from a backend
> and never ships the tenant secret to the client.

## Headless smoke test

`src/smoke.gleam` drives two clients from Node against a running
`just integration-up` server: both clap concurrently with no coordination,
and the tally must converge on the true sum (no lost update), survive a forced
reconnect, and keep counting afterward.

```sh
pnpm install
gleam build --target javascript
pnpm exec esbuild build/dev/javascript/clap_counter_lustre/smoke.mjs \
  --bundle --format=esm --outfile=dist/smoke.mjs
node smoke/run.mjs   # supplies a WebSocket global for phoenix.js
# → SMOKE PASS: concurrent claps converged with no lost update
```
