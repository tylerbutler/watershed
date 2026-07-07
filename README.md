# watershed

A Gleam (BEAM) DDS client toolkit for [levee](https://github.com/tylerbutler/levee) —
collaborative data structures with optimistic local edits, convergence guaranteed
by server sequencing, and reconnect safety. SharedMap is the anchor DDS;
SharedCounter, OR-set, claims, and the other channel kinds ride the same runtime,
and an opt-in [typed document layer](#typed-documents) declares a document's shape
once.

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
│  DDS kernels (PURE)  │  wire (PURE)         │   (M1 ✅ / M3)
│  sequenced + pending │  levee channel       │
│  LWW/delta merge     │  payload codecs      │
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
- **SharedCounter kernel: done.** `watershed/counter_kernel` is a pure port of
  FluidFramework's `counter.ts` delta semantics: integer increments, optimistic
  local apply, FIFO acks, local message-id validation, stashed ops, rollback,
  and summary seeding.
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

The pure core (`map_kernel`, `counter_kernel`, `wire`, `runtime_core`) is
target-agnostic. Two runtimes sit on top:

| Layer | BEAM (`watershed`) | Browser (`watershed_js`) |
| --- | --- | --- |
| Transport | aquamarine (gun / roost) | phoenix.js via FFI |
| Runtime | `runtime` (OTP actor) | `runtime_js` (callbacks + mutable cell) |
| Pure core | `map_kernel` · `counter_kernel` · `wire` · `runtime_core` | ← identical, shared |

The erlang-only modules are gated with `@target(erlang)` so
`gleam build --target javascript` compiles just the pure core plus the JS
runtime. See [`examples/dice_lustre`](examples/dice_lustre) for a Lustre SPA
whose entire client is Gleam, verified converging against a live `just server`,
[`examples/dice_cli`](examples/dice_cli) for its Erlang-target CLI counterpart,
and [`examples/scoreboard_cli`](examples/scoreboard_cli) for a multi-player
scoreboard whose per-player records use the [typed document layer](#typed-documents).

## Typed documents

`watershed/schema` adds an opt-in typed view over a SharedMap: declare a
document's shape once and read/write through it. Typing is a *decode boundary*,
not a closed schema — remote peers (or old summaries) can still write any JSON,
so typed reads return `Result`.

Declare each slot as a field — a plain value, a nested typed map (`ChildField`),
or a handle to any other channel kind (`ChannelField`):

```gleam
import watershed/schema.{type ChannelField, type CounterChannel, type Field}

pub type Doc
pub fn title() -> Field(Doc, String) {
  schema.field("title", json.string, decode.string)
}
pub fn mistakes() -> ChannelField(Doc, CounterChannel) {
  schema.channel_field("mistakes")
}
```

`ensure_*` seeds and adopts the root's channels declaratively, subsuming the
create / race / retry bootstrap apps used to hand-write:

```gleam
let root = watershed.typed(watershed.root(doc))
watershed.ensure_field(root, title(), "Untitled")
let assert Ok(counter) = watershed.ensure_counter(doc, root, mistakes())
```

For a whole record spread across keys, the `record1`..`record9` builders plus
`sealed_known` derive the decoder *and* the encoder from one prop list so they
cannot drift (see [`examples/scoreboard_cli`](examples/scoreboard_cli)). Events
narrow per field or per channel via `subscribe_field` / `subscribe_counter` /
`subscribe_typed`. [`examples/sudoku_lustre`](examples/sudoku_lustre) shows the
full pattern end to end.

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

Map ops are byte-identical to the TS `@fluidframework/map` format
(`{type: "set"|"delete"|"clear", key?, value?: {type: "Plain", value}}`);
SharedCounter ops match `@fluidframework/counter` (`{type: "increment",
incrementAmount}`).
