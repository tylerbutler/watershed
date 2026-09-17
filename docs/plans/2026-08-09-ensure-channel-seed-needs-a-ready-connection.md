# Channel `ensure_*` readiness: fixed

**Date:** 2026-08-09
**Found by:** building `examples/pixel_canvas_lustre`, whose document did not exist yet.
**Status (2026-09-06):** fixed in both `watershed` (JavaScript) and
`watershed_beam`. Channel ensures wait for synchronization before inspecting
the root field, then adopt the replayed handle or seed a new candidate. They
also wait for the candidate's write to synchronize before returning it.

Each synchronization wait uses the existing 25-retry, 200 ms polling budget.
Exhausting it returns `Error("ensure: timed out waiting for document synchronization")`;
it no longer continues as though the wait succeeded. A pre-seed timeout makes
no channel or field write. A post-seed timeout does not roll back an operation
already submitted. `ensure_field` remains synchronous set-if-absent and does
not use this channel-bootstrap path.

The regression suites are `test/watershed/ensure_js_test.gleam` and
`test/watershed/sluice/driver_test.gleam`. They cover fresh-document seeding,
adoption after handshake replay, timeout, closure during a wait, and refusal
to report an unacknowledged seed as success. The BEAM rich-text fixture now
delivers acknowledgements while its blocking ensure runs; previously it
depended on the helper silently succeeding when its wait expired.

The sections below record the original defect and workaround.

## Original defect

`ensure_channel` retries while *resolving* a channel someone else published, but
seeding a new one is a single attempt with no retry and no wait
(`src/watershed_js.gleam:998-1010`):

```gleam
case has(typed_map.map, key) {
  True -> resolve_with_retry(resolve, resolve_attempts, done)
  False ->
    case seed() {
      Error(reason) -> done(Error(reason))          // <- no retry, ever
      Ok(Nil) -> await_synced(document, ...)
    }
}
```

Before the handshake lands, the root map is empty, so `has` is `False` and the
seed path is taken. `create_or_map` (and every other `create_*`) refuses with
`"create_or_map requires a ready document connection"`, and the `ensure_*`
callback fails permanently. There is no second attempt, and the app is left
holding no channel.

## Why it is easy to miss

It only bites when a channel actually has to be **seeded** — the first client on
a document that does not have the key yet. Once any client has published the
channel, `has` is `True` on subsequent loads and the resolve path, which does
retry, papers over the timing entirely.

That is why the existing Lustre examples appear fine. Their documents were
seeded long ago, and their smoke tests seed from Node after an explicit
`delay(2000)` — i.e. after the connection is ready. Reloading
`examples/drum_machine_lustre` in a browser resolves rather than seeds, and
works. A brand-new document opened only from a browser is the case nobody runs.

## Reproduction

Point any Lustre example at a `document_id` that has never existed, bootstrap
from the `GotHandle` arm as the examples do, and read the error banner:

```
create_or_map requires a ready document connection
```

The canvas then paints locally and shares nothing, because the app's write path
is guarded on holding a resolved channel.

## Original workaround

`examples/pixel_canvas_lustre` bootstraps from `Connected(Ok(_))` instead of
`GotHandle`, which is the arm that means "the handshake landed". `GotHandle`
only stores the handle and starts the diagnostics poll. This costs nothing and
is arguably the clearer place for it regardless.

Other examples that bootstrapped from `GotHandle` had the same fresh-document
hazard. The shared library fix removes the need to migrate those callers.
Starting from `Connected(Ok(_))` remains a valid application convention.

## Implemented fix

Both facades call `await_synced` before the `has` check. The helper returns a
`Result`, and both the pre-seed and post-seed paths propagate its error. This
also closes the coupled timeout bug: an expired post-seed wait used to resolve
the optimistic local handle and report success without an acknowledgement.

Public channel-ensure signatures are unchanged. The JavaScript facade uses
callbacks; the BEAM facade blocks and returns the same result shape.
