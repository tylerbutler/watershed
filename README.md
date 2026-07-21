# watershed

A Gleam Fluid Framework DDS client toolkit for Erlang and JavaScript. It provides
collaborative data structures with optimistic local edits, convergence through
server sequencing, and reconnect safety. SharedMap is the anchor DDS;
SharedCounter, SharedSequence, OR-set, claims, and the other channel kinds share
the same runtime. An opt-in [typed document layer](#typed-documents) declares a
document's shape once. [levee](https://github.com/tylerbutler/levee) is one
compatible server implementation.

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
- **SharedSequence kernel: done.** `watershed/sequence_kernel` uses
  `lattice_sequence` for optimistic insert, delete, and move operations over
  arbitrary JSON values, with summaries, stashed ops, rollback, and
  multi-client convergence.
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

The pure core (`map_kernel`, `counter_kernel`, `sequence_kernel`, `wire`,
`runtime_core`) is target-agnostic. Two runtimes sit on top:

| Layer | BEAM (`watershed`) | Browser (`watershed_js`) |
| --- | --- | --- |
| Transport | aquamarine (gun / roost) | phoenix.js via FFI |
| Runtime | `runtime` (OTP actor) | `runtime_js` (callbacks + mutable cell) |
| Pure core | `map_kernel` · `counter_kernel` · `sequence_kernel` · `wire` · `runtime_core` | ← identical, shared |

The erlang-only modules are gated with `@target(erlang)` so
`gleam build --target javascript` compiles just the pure core plus the JS
runtime. See [`examples/dice_lustre`](examples/dice_lustre) for a Lustre SPA
whose entire client is Gleam, verified converging against a live `just server`,
[`examples/dice_cli`](examples/dice_cli) for its Erlang-target CLI counterpart,
and [`examples/scoreboard_cli`](examples/scoreboard_cli) for a multi-player
scoreboard whose per-player records use the [typed document layer](#typed-documents).

For Lustre apps, [`watershed_lustre`](watershed_lustre) binds the JS facade to
Lustre as effects — `connect`, per-kind subscriptions, `ensure_*` bootstrap, and
a presence effect — so an app declares its wiring instead of hand-bridging
watershed's callbacks into `dispatch` (and deferring each to dodge the
mid-`update` clobber). Both Lustre examples are built on it.

## Shared sequences

`SharedSequence` is a collaborative Array-like DDS that stores arbitrary JSON
values. The Erlang and JavaScript facades expose the same create, resolve,
insert, delete, move, replace, read, and subscription operations:

```gleam
import gleam/json

let assert Ok(items) = watershed.create_sequence(doc)
let assert Ok(Nil) =
  watershed.sequence_insert(items, 0, json.string("first"))
let assert Ok(Nil) =
  watershed.sequence_insert(items, 1, json.string("second"))
let assert Ok(Nil) = watershed.sequence_move(items, 0, 1)
watershed.sequence_values(items)
// [json.string("second"), json.string("first")]
```

Move destinations are interpreted after removing the source value. Replace is
one Watershed operation composed by merging `lattice_sequence` delete and insert
deltas; `lattice_sequence` has no native replace primitive. This Array-like DDS
is the foundation for collaborative text editing, but watershed does not yet
expose a text-specific API.

## Typed documents

`watershed/schema` adds an opt-in typed view over a SharedMap: declare a
document's shape once and read/write through it. Typing is a *decode boundary*,
not a closed schema — remote peers (or old summaries) can still write any JSON,
so typed reads return `Result`.

Declare each slot as a field — a plain value, a nested typed map (`ChildField`),
or a handle to any other channel kind (`ChannelField`):

```gleam
import watershed/schema.{
  type ChannelField,
  type CounterChannel,
  type Field,
  type SequenceChannel,
}

pub type Doc
pub fn title() -> Field(Doc, String) {
  schema.field("title", json.string, decode.string)
}
pub fn mistakes() -> ChannelField(Doc, CounterChannel) {
  schema.channel_field("mistakes")
}
pub fn items() -> ChannelField(Doc, SequenceChannel) {
  schema.channel_field("items")
}
```

`ensure_*` seeds and adopts the root's channels declaratively, subsuming the
create / race / retry bootstrap apps used to hand-write:

```gleam
let root = watershed.typed(watershed.root(doc))
watershed.ensure_field(root, title(), "Untitled")
let assert Ok(counter) = watershed.ensure_counter(doc, root, mistakes())
let assert Ok(sequence) = watershed.ensure_sequence(doc, root, items())
```

For a whole record spread across keys, the `record1`..`record9` builders plus
`sealed_known` derive the decoder *and* the encoder from one prop list so they
cannot drift (see [`examples/scoreboard_cli`](examples/scoreboard_cli)). Events
narrow per field or per channel via `subscribe_field`, `subscribe_counter`,
`subscribe_sequence`, and `subscribe_typed`.
[`examples/sudoku_lustre`](examples/sudoku_lustre) shows the full pattern end to
end.

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

## Testing your app (the sluice)

`watershed/sluice` (erlang) and `watershed/sluice_js` (JavaScript) are an
**in-memory levee**: a deterministic, single-process stand-in for the server so
you can write multi-client convergence tests with no infrastructure. It runs the
*real* runtime — same codecs, pending queues, resubmit, reconnect catch-up — over
an injected transport, and the *real* server sequencing (spillway's `sequencing`
module), so a passing sluice test exercises production code paths end to end.

Delivery is **explicit**: ops sequence when submitted but arrive only when you
call `settle` (deliver until quiescent) or `step` (deliver one frame). That makes
races scriptable — "both clients claim the cell, deliver B first" is a sequence
of calls, not a timing accident — and makes assertions deterministic without
polling.

```gleam
// JavaScript (browser/Lustre apps); erlang is identical via watershed/sluice.
import watershed/sluice_js
import watershed_js

pub fn two_clients_converge_test() {
  let sluice = sluice_js.start(tenant: "default", document: "demo")
  let doc_a = sluice_js.connect(sluice, "user-a")
  let doc_b = sluice_js.connect(sluice, "user-b")
  sluice_js.settle(sluice)                       // complete both handshakes

  watershed_js.set(watershed_js.root(doc_a), "k", json.int(1))
  sluice_js.settle(sluice)                       // deliver the edit everywhere

  watershed_js.get(watershed_js.root(doc_b), "k")  // Some(json.int(1))
}
```

Controls: `settle`, `step`, `pause`/`resume` (erlang — hold a client's frames to
script delivery order), and `advance(ms)` (move the sluice's logical clock so
presence TTL logic is testable without sleeping). The live-server integration
suite stays authoritative and untouched; the sluice models levee, it is not
levee. See `examples/sudoku_lustre/test/convergence_test.gleam` for a real app
test, and `docs/plans/2026-07-06-in-memory-hub-plan.md` for the design.
