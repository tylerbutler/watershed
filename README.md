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
- M2 — shared test corpus against the TS `MapKernel` oracle: not started.
- M3+ — wire codecs, runtime actor, resilience, public API: not started.

## Development

```sh
gleam test    # unit + property tests
gleam format
```

Ops are byte-identical to the TS `@fluidframework/map` format
(`{type: "set"|"delete"|"clear", key?, value?: {type: "Plain", value}}`);
values are `gleam/json` values in v1.
