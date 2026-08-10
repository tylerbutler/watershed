# Pixel canvas (Lustre)

A shared 64×64 bitmap. Two tabs paint over each other and either end up with the
same picture or they don't — which is the point.

Every other example here proves convergence by assertion: the dice example shows
a number, sudoku a grid of digits, the scoreboard a total. You have to accept
that the number is right. A bitmap removes that step and lets you adjudicate it
yourself, without reading any Gleam.

```sh
just integration-up                                  # floodgate on :4000
pnpm install && pnpm run build
pnpm run serve                                       # then open :8080 in two tabs
```

## What it demonstrates

**Uncoordinated last-writer-wins, per cell.** The canvas is one `OrMap` channel
in `RegisterMode`, keyed by cell, holding a palette index. Two people painting
different cells never interact. Two people painting the *same* cell settle on
one colour with nobody waiting for anybody.

Deliberately **not** a `PactMap`. That is the quorum protocol, where a value
stays pending until a frozen signoff list drains — requiring the room to agree
before a pixel changes colour is the opposite of what a paint canvas wants. And
deliberately not a `SharedMap`, which three other examples already cover.

**Op volume.** This is the only example that emits ops in the thousands. A drag
crosses a cell boundary many times a second, and every crossing is an op through
the same path that elsewhere only ever carries one keystroke at a time.

**Convergence by join.** `or_map_kernel` advances state by joining sparse
deltas, so two clients that painted disjoint regions while apart converge by
join rather than by replaying each other's ops.

## Key and value encoding

Keys are `"<x>,<y>"`, zero-padded to two digits: `"07,31"`. The padding is not
decoration — unpadded keys sort as text, which puts `"7,0"` between `"60,0"` and
`"8,0"`, and a fixed width is what makes a dump of the summary blob readable as
a picture instead of as scrambled coordinates. Sorted, the keys walk the grid
column by column.

Values are the palette index as a decimal string, `"0"`–`"15"`. Erasing writes
index `0` rather than calling `or_map_remove`: a canvas has no notion of an
absent pixel, and keeping the key avoids the remove/re-add tombstone paths,
which are not what this example is about. (Those get their workout in the retro
board.) Index `0` clears the pixel rather than filling it, so an erased cell
shows the element's CSS background and the canvas follows light/dark mode
without the app knowing which is in force.

## Bootstrap waits for the handshake

The `ensure_*` calls live in the `Connected(Ok(_))` arm, not in `GotHandle` as
the other Lustre examples do. `ensure_*` retries while *resolving* a channel
someone else published, but seeding a new one is a single attempt — on a
document whose root map is still empty, `create_or_map` refuses with "requires a
ready document connection" and the callback fails for good, leaving the app
painting locally and sharing nothing. See
[`docs/plans/2026-08-09-ensure-channel-seed-needs-a-ready-connection.md`](../../docs/plans/2026-08-09-ensure-channel-seed-needs-a-ready-connection.md).

## The canvas is owned by the FFI

`src/canvas_ffi.mjs` owns a `Uint8Array` and the 2D context outright. Lustre
renders `<canvas id="canvas">` and nothing inside it — `html.canvas` takes no
children, so that much is enforced by the type. 4096 vdom nodes re-diffed on
every remote event would dominate the profile and make watershed look slow for
reasons that have nothing to do with watershed.

Two rules keep it working, and both will bite if broken:

1. **`width` and `height` must stay static in `view`.** Re-setting either resets
   the drawing surface, so a diff that rewrites them wipes the picture.
2. **The context is resolved lazily on every call**, and the module no-ops until
   the element exists. This is why no mount-ordering effect is needed: state
   arriving before the first paint is written to the buffer, and the buffer is
   flushed the moment the element appears.

The bitmap is 64×64 scaled up by CSS with `image-rendering: pixelated`, so one
cell is one canvas pixel, a paint is `fillRect(x, y, 1, 1)`, and there is no
device-pixel-ratio arithmetic anywhere.

## The offline toggle, and a caveat

"Go offline" calls `watershed_js.go_offline`, which holds the socket down —
distinct from `force_reconnect`, which is away-and-back in one step and leaves no
window to edit in, and from `close`, which is terminal. The document keeps
serving reads and accepting edits while held; the status line shows
`in_flight_count`, the number of cells waiting to reach the server.

**Coming back does not currently work against a live server.** The JS runtime
stalls in `catching-up` after any reconnect that spans sequenced ops, and never
receives what it missed. This is not a fault of the toggle — the shipped
`force_reconnect` reproduces it on a fresh document with nothing in flight — and
it is written up in
[`docs/plans/2026-08-09-js-reconnect-catchup-defect.md`](../../docs/plans/2026-08-09-js-reconnect-catchup-defect.md).

So: going offline, painting while held, and staying isolated from the room all
work and are asserted in the smoke test. The return leg is asserted only at the
kernel level, in `test/convergence_test.gleam`, where the in-memory sluice drives
it and it passes.

## Tests

```sh
gleam test        # convergence + key codec, no server, no browser
pnpm run smoke    # against a live floodgate (just integration-up)
```

`test/convergence_test.gleam` drives two in-process clients over `sluice_js` and
asserts what the demo claims out loud: disjoint regions converge, a contested
cell settles the same way for everyone, a late joiner replays the picture, and a
stroke made offline arrives on reconnect.

`test/grid_test.gleam` checks the key codec over all 4096 cells. Exhaustive
rather than sampled — the domain is small enough, it is stronger than any
property run, and an example package has no property library available anyway.

There is no test for the canvas FFI. It is pure rendering, and the convergence
tests cover the state it renders from.

One thing the tests deliberately do not assert: which colour wins a contested
cell. Register leaves are last-writer-wins on a millisecond wall clock,
tie-broken by replica id, so writes that share a millisecond resolve to the
earliest rather than the latest. The demo promises the room agrees, not who
wins.
