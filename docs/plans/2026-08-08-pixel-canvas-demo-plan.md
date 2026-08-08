# Pixel canvas demo plan — convergence you can see

**Date:** 2026-08-08
**Builds on:** `2026-07-06-lustre-integration-plan.md` (LU1–LU3, shipped — `watershed_lustre.connect_dev` / `subscribe_or_map` are the whole bridge this needs), `2026-07-03-or-map-kernel-plan.md` (shipped, commit `82f0db6`).
**Benchmark:** r/place. Every collaborative-sync product eventually builds one, because a shared bitmap is the only demo where the reader verifies convergence with their eyes instead of trusting a number.

**Prerequisite work: none.** Every call this example needs already exists on the JS facade and in `watershed_lustre`. This is the cheapest of the three demo plans and should ship first.

## Decisions already made (flagged — confirm before PX1)

1. **`OrMap` in `RegisterMode`, one channel, keyed `"x,y"`.** Not `SharedMap` (already demoed three times over), and explicitly **not `PactMap`** — `PactMap` is Fluid's *quorum* protocol, where a set stays pending until a frozen signoff list drains (`src/watershed/pact_map_kernel.gleam:1-5`). Requiring a room-wide quorum per pixel is the exact opposite of what a paint canvas wants. `OrMap` register leaves are LWW per key with no coordination, which is right.
2. **The canvas is a lattice CRDT, and that is the point of the demo.** `or_map_kernel` advances state by joining sparse deltas, so two clients that paint disjoint regions while disconnected converge by *join* on reconnect — no rebase, no op replay, no server arbitration. The offline toggle (PX4) is not a bonus feature; it is the thesis.
3. **Fixed 64×64 grid, 16-color palette, no zoom or pan.** 4096 keys is enough to look like a picture and small enough that a full `or_map_entries` read per frame stays honest. Zoom/pan is view state with no collaborative content and would only add code that does not exercise watershed.
4. **Render to a single `<canvas>` via FFI, not 4096 vdom nodes.** Lustre's diff over a 4096-element grid on every remote event would dominate the profile and make the demo look slow for reasons that have nothing to do with watershed. The Lustre app owns state, palette, toolbar, and status; one `before_paint` effect blits changed cells.
5. **No presence in v1.** Cursor presence is a strong addition but it is the `bench_book_lustre` story already, and it competes for attention with the convergence story. Listed as PX6, explicitly optional.

## Why this demo

The existing examples all prove convergence by *assertion*: the dice example shows a number, sudoku shows a grid of digits, the scoreboard shows totals. A reader has to accept that the number is right. A bitmap removes that step — two tabs painting overlapping regions either produce the same picture or they don't, and the reader adjudicates without reading a line of Gleam.

It is also the only demo on the roadmap that stresses **op volume**. Dragging the brush emits one op per cell entered; a few seconds of scribbling in two tabs is thousands of ops through the same path that currently only ever sees a keystroke at a time. That is worth having as a standing artifact, not just a benchmark run.

## Data model

Schema (one channel on the root typed map):

```gleam
// examples/pixel_canvas_lustre/src/doc_schema.gleam
pub type Canvas

pub const pixels: ChannelField(Canvas, schema.OrMapChannel) = ...
```

Bootstrap mirrors every other example:

```gleam
watershed_js.ensure_or_map(
  document,
  watershed_js.root_typed(document),
  doc_schema.pixels,
  or_map_kernel.RegisterMode,
  EnsuredPixels,
)
```

**Key encoding:** `"<x>,<y>"`, zero-padded to two digits so keys sort lexicographically into row-major order (`"07,31"`). Padding buys a stable, sortable key for free and makes the summary blob readable when debugging.

**Value encoding:** the palette index as a decimal string (`or_map_set(pixels, key, "11")`). `Register` leaves hold a `String` (`or_map_kernel.OrMapValue = Tally(Int) | Register(String)`), so a one-byte-ish payload keeps ops small — which matters precisely because this demo emits a lot of them. Erasing sets index `"0"` (transparent) rather than calling `or_map_remove`; a canvas has no notion of an absent pixel, and keeping the key avoids exercising remove/re-add tombstone paths that are not what this demo is about. (`or_map_remove` gets its workout in the retro board.)

## Message flow

```gleam
type Msg {
  GotDocument(watershed_js.Document)
  Connected(Result(Nil, String))
  EnsuredPixels(Result(watershed_js.OrMap, String))
  PixelsChanged(or_map_kernel.OrMapEvent)
  PalettePicked(Int)
  PointerDown(x: Int, y: Int)
  PointerMoved(x: Int, y: Int)
  PointerUp
  ToggledOffline(Bool)
}
```

**Local paint** (`PointerDown` / `PointerMoved` while down): map client coordinates to a cell, skip if it equals the last-painted cell (the pointer fires far more often than it crosses cell boundaries — this dedupe is the difference between ~40 ops/sec and ~400), then `or_map_set`. The optimistic write lands in the model's cell array immediately and the `PixelsChanged` subscription re-confirms it a microtask later, exactly as the textarea component does.

**Remote paint** (`PixelsChanged(RegisterUpdated(key, value))`): decode the key, write the palette index into the model's cell array, push the cell onto a dirty list. `KeyRemoved` clears to transparent (defensive — this app never emits removes, but a peer on a future version might). `TallyUpdated` is unreachable in `RegisterMode`; fold it to a no-op rather than crashing.

**Rendering:** the model holds a flat 4096-entry array of palette indices plus a dirty-cell list. `effect.before_paint` hands the root element to an FFI `blit(root, instance, dirty_cells, palette)` that fills only the dirty rectangles and clears the list. Full repaint happens once, on `EnsuredPixels`, when the joiner receives existing canvas state.

## The offline toggle

The demo's headline control. `ToggledOffline(True)` drops the transport; the user keeps painting and every stroke lands optimistically; `ToggledOffline(False)` reconnects and the two canvases join. The status bar shows connection state and a pending-op count throughout.

**Open question, resolve during PX4:** whether the JS transport exposes a clean disconnect/reconnect that `watershed_lustre` can drive, or whether the demo has to tear down and re-`connect` to the same document. `src/watershed/transport_ffi.mjs` and `transport_js.gleam` are the places to look. If only teardown-and-reconnect works, the demo is still correct (the summary replay path is what gets exercised), but say so in the README rather than implying a graceful link-drop.

## Rungs

- **PX1 — scaffold.** `examples/pixel_canvas_lustre/` copying `playlist_lustre`'s `gleam.toml` / `package.json` / `index.html` / `pnpm-workspace.yaml` shape. Add install + build stanzas to `justfile` alongside the other four examples. Gate: `pnpm build` produces `dist/pixel_canvas_lustre.mjs`.
- **PX2 — connect and bootstrap.** `connect_dev`, `ensure_or_map` in `RegisterMode`, `subscribe_or_map`. Render a static grid of the initial state, no interaction. Gate: two tabs against a floodgate dev server (`just integration-up`) both render an empty canvas and log the ready handshake.
- **PX3 — paint.** Palette, pointer handling with cell dedupe, canvas FFI blit, optimistic + remote paths. Gate: two tabs, paint overlapping regions, both converge to the same picture.
- **PX4 — offline toggle.** Disconnect control, pending-op counter, reconnect and join. Gate: paint disjoint regions in two disconnected tabs; on reconnect both show the union. Paint the *same* cell in both while disconnected; both settle on the same colour (whichever the LWW join picks — the demo must not claim which).
- **PX5 — README + smoke test.** `smoke/run.mjs` following the sudoku/playlist pattern; README documents the key encoding, why `OrMap` over `PactMap`, and the reconnect caveat from PX4.
- **PX6 — presence cursors (optional).** Other painters' cursors via `presence_js`, coloured by `presence.color_for`. Defer unless PX1–PX5 land cheaply.

## Testing strategy

- **Convergence test** (`test/convergence_test.gleam`, following `examples/sudoku_lustre/test/`): drive two in-process clients over `sluice`, issue interleaved paints including same-cell conflicts, assert identical `or_map_entries` on both. This is the assertion the visual demo makes informally.
- **Key codec property test:** `encode(x, y) |> decode == Ok(#(x, y))` across the full 64×64 range, and that encoded keys sort row-major.
- **Smoke test:** bundle-loads under Node with a `ws` global, connects, paints one cell, reads it back.
- No test for the FFI blit — it is pure rendering, and the convergence test covers the state it renders from.
