# watershed

A Gleam (BEAM) DDS client toolkit for [levee](https://github.com/tylerbutler/levee) —
collaborative data structures with optimistic local edits, convergence guaranteed
by server sequencing, and reconnect safety. The first DDS is SharedMap.

Plan: [docs/plans/2026-07-01-gleam-sharedmap-client-plan.md](docs/plans/2026-07-01-gleam-sharedmap-client-plan.md).

## Architecture

```
┌─────────────────────────────────────────────┐
│  Public API: connect, map handle, subscribe │   (M5)
├─────────────────────────────────────────────┤
│  Runtime actor ("delta manager")            │   (M3/M4)
│  handshake · CSN/RSN · inbound ordering ·   │
│  catch-up · resubmit · nack · event fan-out │
├──────────────────────┬──────────────────────┤
│  map_kernel (PURE)   │  wire (PURE)         │   (M1 ✅ / M3)
│  sequenced + pending │  levee channel       │
│  LWW merge, acks     │  payload codecs      │
├──────────────────────┴──────────────────────┤
│  aquamarine (channel client, roost codec)   │
└─────────────────────────────────────────────┘
```

## Status

- **M1 — kernel: done.** `watershed/map_kernel` is a pure port of FluidFramework's
  `mapKernel.ts` (sequenced + pending state, lifetimes, event suppression,
  insertion-order iteration). Unit tests plus qcheck properties: convergence
  across authorship/submit-timing interleavings, ack transparency, and rebase
  equivalence, at 1000 iterations each.
- **M2 — shared test corpus: done.** 20 scenarios generated from the TS
  `MapKernel` oracle and replayed against `map_kernel` in a multi-client sim.
- **M3 — wire + happy-path runtime: done.** `watershed/wire` codecs over
  spillway types; `watershed/runtime_core` pure state machine; `watershed/runtime`
  OTP actor over aquamarine. Two BEAM clients converge against a live server.
- **M4 — resilience: done.** Out-of-order buffering + in-band `requestOps`,
  reconnect/reconcile with client-id remap, nack policy, noop heartbeat.
- **M5 — polish + example: in progress.** Public API (`watershed`), and a
  **Gleam-end-to-end Lustre** dice roller (see below).

## Targets

The pure core (`map_kernel`, `wire`, `runtime_core`) is target-agnostic. Two
runtimes sit on top:

| Layer | BEAM (`watershed`) | Browser (`watershed_js`) |
| --- | --- | --- |
| Transport | aquamarine (gun / roost) | phoenix.js via FFI |
| Runtime | `runtime` (OTP actor) | `runtime_js` (callbacks + mutable cell) |
| Pure core | `map_kernel` · `wire` · `runtime_core` | ← identical, shared |

The erlang-only modules are gated with `@target(erlang)` so
`gleam build --target javascript` compiles just the pure core plus the JS
runtime. See [`examples/dice_lustre`](examples/dice_lustre) for a Lustre SPA
whose entire client is Gleam, verified converging against a live `just server`,
[`examples/dice_cli`](examples/dice_cli) for its Erlang-target CLI counterpart,
and [`examples/scoreboard_cli`](examples/scoreboard_cli) for a multi-player
scoreboard built on nested SharedMaps (`create_map` / `handle_of` / `resolve`).

## Development

```sh
gleam deps download
gleam test                      # BEAM: unit + property + corpus tests
gleam build --target erlang     # BEAM: OTP runtime
gleam build --target javascript # browser: pure core + JS runtime
pnpm --dir examples/dice_lustre install
pnpm --dir examples/dice_lustre run build
gleam format
```

Or use the root justfile:

```sh
just deps
just test
just build
just format
just lint
```

Ops are byte-identical to the TS `@fluidframework/map` format
(`{type: "set"|"delete"|"clear", key?, value?: {type: "Plain", value}}`);
values are `gleam/json` values in v1.
