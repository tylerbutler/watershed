# A reconnecting client never finished catching up

**Date:** 2026-08-09
**Found by:** building `examples/pixel_canvas_lustre`
(`2026-08-08-pixel-canvas-demo-plan.md`), whose offline toggle is the first
thing in the repo to reconnect a JS client across a gap with real traffic in it.
**Status:** fixed. The fix, its tests, and the corrections to this document are
all in the same commit range as this line.

## The defect

A client that reconnected while anyone else had been editing settled into the
`catching-up` phase and stayed there. It never received the ops it missed, and
nothing it did afterwards reached the server. The document was dead until the
page was reloaded.

The rejoin handshake itself succeeded — the client learned the room's current
sequence number and set a resubmit checkpoint from it — so this was never a
connection failure. It was a catch-up that nobody had asked for.

## Root cause

The catch-up was reactive, and nothing was there to react to.

1. **The reconnect path does not replay history.** `runtime_core.bootstrap`
   replays `connected.initial_messages`; `runtime_core.adopt_reconnect`
   deliberately does not, because the core already holds that history.
2. **So only an inbound op can close the gap.** `settle_reconnect` promotes out
   of the holding state once `last_seen_sn >= checkpoint`, and the only thing
   that advances `last_seen_sn` is `handle_sequenced`. The only catch-up trigger
   was that same function noticing a *non-contiguous* op and returning
   `request_ops_from` — which needs an op to arrive first.
3. **No server sends one.** Floodgate ignores `lastSeenSequenceNumber` outright
   (the field is not read anywhere in its source, despite the wire codec's
   comment promising "automatic delta catch-up"), and it excludes the joiner
   from the broadcast of the joiner's *own* join op — `broadcast_from(channels,
   cid, ...)`, whose comment explains the exclusion is to avoid an early
   duplicate. A client rejoining a room nobody else is writing to receives
   nothing at all.

Recovery therefore depended on incidental traffic arriving after the rejoin. A
quiet room waits forever.

That dependency is also why the two runtimes behaved so differently in practice
despite sharing the code. The BEAM transport rebuilds its socket immediately, so
a client is usually back before the server finishes tearing the old one down —
and the `leave` floodgate then sequences for the client's *previous* identity is
broadcast to the whole topic, its own new socket included. That stray op closed
the gap by accident. The JS transport rejoins on Phoenix's backoff, which opens
a window wide enough that the `leave` is sequenced and gone before the client is
listening again. Same defect, one runtime quietly rescued by a race.

It was also worse than first reported. Floodgate sequences the rejoining
client's own `join` and reports **that** SN as the handshake checkpoint, so a
reconnect is behind its checkpoint even when it missed no application traffic
whatsoever. Reconnecting into total silence wedged with an empty gap.

### The fix

`runtime_core.catch_up_from(core, checkpoint)`, called from the `Reconnecting`
branch of `connect_document_success` in both runtimes: when the handshake lands
ahead of `last_seen_sn`, push `requestOps {from: last_seen_sn}` once. Both
floodgate and the sluice already answered that message; the client simply never
sent it on this path.

Deliberately not inside `settle_reconnect`, which is also called from the `op`
handler for every op received while catching up — putting it there would
re-request the whole gap per op.

## Why it survived this long

Not "the JS runtime had no live coverage", though that was true and is now
fixed. **The BEAM runtime had the identical defect.** The two runtimes share
`runtime_core` and their reconnect handlers are line-for-line the same; only the
transport differs.

What differed was the *shape of the tests*:

- `test/watershed/integration_test.gleam`'s `reconnect_converges_test` has B
  editing and a third client joining after A comes back. Either supplies the
  out-of-order op that triggers the reactive `requestOps`. The scenario was
  never quiet, so the stall never appeared.
- Every sluice-level reconnect test passed because **the sluice pushed a frame
  no real server sends**: the joiner's own join op, echoed back to the joiner
  after the handshake. Its comment called that push "load-bearing on the
  reconnect path", and it was — it was standing in for a catch-up that never
  happened. It also claimed to be "how the real server orders it", which was the
  part that was wrong.

An earlier draft of this document credited
`reconnect_applies_missed_delta_from_others_test` and
`reconnect_catch_up_replays_exactly_the_gap_test` to the live BEAM suite as
proof the BEAM path worked. They are not in it. The first is a pure
`runtime_core` unit test that hand-feeds the gap ops in, so it asserts the core
*would* apply a delta if one were delivered — the stall was in delivery. The
second was a sluice test asserting the sluice honoured `lastSeenSequenceNumber`,
which floodgate does not.

## What changed

- `runtime_core.catch_up_from`, wired into `runtime.gleam` and
  `runtime_js.gleam`.
- `sluice/core.gleam` now models floodgate: no self-join push, `initialMessages`
  unfiltered by `lastSeenSequenceNumber`, and `requestOps` exclusive of `from`
  (it was one op generous, which meant it could never catch an off-by-one in the
  client). Five reconnect and offline-window tests fail without the runtime fix
  now; before the sluice was corrected, none could.
- `test/live_js.gleam` — the JS runtime's first live suite, run by
  `just integration-run-js`. It is a `main` rather than `gleam test` cases
  because startest's `TestBody` is `fn() -> Nil`, which would score every
  assertion in an async suite before it ran. All three scenarios were confirmed
  to fail with the fix reverted and pass with it restored; that is the live gate
  for this defect.
- `reconnect_into_a_quiet_room_test` and
  `reconnect_with_nothing_missed_settles_test` in the BEAM live suite — the
  cases whose defining feature is the *absence* of post-reconnect traffic. These
  are coverage, **not** a gate: both pass with the fix reverted, for the
  race-rescue reason above, and their doc comments say so.
- `examples/pixel_canvas_lustre/src/smoke.gleam` asserts the return leg again.

One thing worth noting about reproducing this, because it cost time: with
`force_reconnect` the client is usually back within a second, so a peer's write
lands *after* the rejoin — where it is an ordinary out-of-order op that triggers
the reactive catch-up, and the scenario passes whether or not the handshake asks
for anything. Only holding the socket down with `go_offline` puts the write
reliably inside the gap.

## The lesson worth keeping

A test double that compensates for a behaviour the real system lacks does not
just fail to catch the bug — it actively certifies the broken code. The sluice's
extra frame was added in good faith, documented carefully, and described as
matching the real server. Nobody checked that claim against floodgate, and it
bought a green suite for a client that could not reconnect.
