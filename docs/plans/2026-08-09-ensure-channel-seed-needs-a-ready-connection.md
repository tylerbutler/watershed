# `ensure_*` cannot seed a channel before the handshake lands

**Date:** 2026-08-09
**Found by:** building `examples/pixel_canvas_lustre`, whose document did not exist yet.
**Status:** reproduced; worked around in the example, not fixed in the library.

## The defect

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

## The workaround

`examples/pixel_canvas_lustre` bootstraps from `Connected(Ok(_))` instead of
`GotHandle`, which is the arm that means "the handshake landed". `GotHandle`
only stores the handle and starts the diagnostics poll. This costs nothing and
is arguably the clearer place for it regardless.

The other Lustre examples still bootstrap from `GotHandle` and would fail the
same way on a fresh document. Moving them is a small, mechanical change.

## The fix

Make seeding wait for the connection the way resolving retries for the handle —
`await_synced` already exists and is used immediately *after* `seed()` succeeds.
Hoisting it above the `has` check would make `ensure_*` correct from any arm and
remove the ordering trap from the API rather than from each caller.

Worth a test that seeds a channel on a genuinely fresh document from a
not-yet-ready connection; the current suites never do, on either target.
