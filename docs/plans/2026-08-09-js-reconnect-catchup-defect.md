# The JS runtime never finishes catching up after a reconnect

**Date:** 2026-08-09
**Found by:** building `examples/pixel_canvas_lustre` (`2026-08-08-pixel-canvas-demo-plan.md`), whose offline toggle is the first thing in the repo to reconnect a JS client across a gap with real traffic in it.
**Status:** reproduced, not fixed. Independent of the offline toggle — the shipped `force_reconnect` reproduces it.

## The defect

A JavaScript client that reconnects while anyone else has been editing settles
into the `catching-up` phase and stays there. It never receives the ops it
missed, and nothing it does afterwards reaches the server. The document is dead
until the page is reloaded.

The rejoin handshake itself succeeds — the client learns the room's current
sequence number and sets a resubmit checkpoint from it — so this is not a
connection failure. It is the catch-up that never arrives.

## Reproduction

Against `just integration-up`, on a **fresh** document, using only shipped API:

```gleam
// A and B are connected and settled; the room is at sequence 4.
watershed_js.force_reconnect(doc_a)
paint(b, 3, 3, 8)          // B writes into the window A's reconnect opens
// ...wait 6s...
color_at(a, 3, 3)          // MISSING
watershed_js.diagnostics(doc_a)
// phase=catching-up last_seen=4 in_flight=0 resubmit=7
```

`in_flight=0` (nothing of A's to resubmit) and `buffered_out_of_order_count=0`
(nothing arrived and got held back). `last_seen` never moves off 4 while the
checkpoint sits at 7, so ops 5–7 are simply never delivered to the client.

Waiting longer does not help — the state is identical at 3s, 6s and 12s. It is a
stall, not a slow path.

Freshness matters when reproducing: once a client is stuck it stays stuck, so a
probe that runs several scenarios against one client will show every scenario
after the first as failing regardless of cause. Use a new document and new
clients per case.

The same stall appears through `go_offline`/`go_online`, with or without local
edits made during the gap — which is what rules out resubmit as the cause. The
minimal failing case is "be away while someone else writes".

## Why it survived this long

The two runtimes have very different coverage:

- **BEAM is tested live and works.** `test/watershed/integration_test.gleam`
  drives the `watershed` (erlang) facade against floodgate under
  `WATERSHED_INTEGRATION=1`. All 18 reconnect tests pass, including
  `reconnect_applies_missed_delta_from_others_test` and
  `reconnect_catch_up_replays_exactly_the_gap_test` — precisely this scenario.
  (The suite's one failure, `summary_versions_test`, is the known floodgate gap
  and unrelated.)
- **The JS runtime has no live coverage at all.** It is only ever exercised
  against the in-memory `sluice_js`, which models the rejoin differently and by
  its own admission: it never re-runs `Transport.connect`, and it hands the
  client a fresh server-assigned id synchronously (`sluice_js.gleam:166-171`).
  Every sluice-level reconnect test passes, including the ones added for the
  pixel canvas.

So the gap is not "nobody tested reconnect" — it is that reconnect is tested on
the runtime that works, through a driver that does not model the failing path.

## Where to look

- `src/watershed/runtime_js.gleam` — the rejoin path. `on_join` fires (the phase
  does move to `Ready(core, Some(checkpoint))`, which is what `catching-up`
  renders), so the question is what `connect_document` carries on a *re*-join
  versus a first join, and whether floodgate's reply is being routed anywhere.
- Compare against `src/watershed/runtime.gleam`'s reconnect handling, which
  passes the same scenario live.
- Worth ruling out early: whether floodgate treats a rejoined phoenix socket as
  a new client and answers with a bootstrap the JS client then ignores.

## What this blocks

`examples/pixel_canvas_lustre`'s offline toggle. Going offline works correctly
against a real server — the socket is held, the client keeps painting, and the
edits are isolated from the room — and all of that is asserted in the example's
smoke test. Coming back is disabled there, with a pointer to this document.

When it is fixed, restore the return leg in
`examples/pixel_canvas_lustre/src/smoke.gleam`: paint an offline stroke,
`go_online`, and assert B sees every cell of it and A sees what it missed while
away. The example's sluice-level convergence tests already assert exactly that
shape and pass, so they are the specification to match.

## Suggested first step

Give the JS runtime the live coverage it has never had. A JS counterpart to the
BEAM integration suite — even just `reconnect_applies_missed_delta_from_others`
ported to `watershed_js` and run under `WATERSHED_INTEGRATION=1` — turns this
from an anecdote into a regression test, and would have caught it.
